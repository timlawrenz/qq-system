# frozen_string_literal: true

module TradingStrategies
  # GenerateContractsPortfolio
  #
  # Generates target positions based on recent government contract awards that pass
  # minimum absolute value and materiality filters.
  class GenerateContractsPortfolio < GLCommand::Callable
    allows :lookback_days, :min_materiality_pct, :min_contract_value,
           :holding_period_days, :sector_thresholds, :preferred_agencies,
           :sizing_mode, :total_equity

    returns :target_positions, :stats, :filters_applied

    def call
      set_defaults
      validate_inputs

      equity = validate_equity!

      contracts = fetch_recent_contracts
      context.stats = { total_contracts: contracts.size }

      filtered = apply_filters(contracts)
      context.stats[:contracts_after_filters] = filtered.size

      weights = build_weights(filtered)
      context.stats[:unique_tickers] = weights.size

      context.target_positions = build_positions(weights, filtered, equity)

      context
    end

    private

    def set_defaults
      context.lookback_days ||= 7
      context.holding_period_days ||= 5
      context.min_materiality_pct ||= 1.0
      context.min_contract_value ||= 10_000_000
      context.sizing_mode ||= 'equal_weight'
      context.sector_thresholds ||= {}
      context.preferred_agencies ||= []

      # Prevent holding_period_days from exceeding lookback_days since we do not persist
      # per-position entry dates yet.
      if context.holding_period_days.to_i > context.lookback_days.to_i
        Rails.logger.warn(
          '[ContractsStrategy] holding_period_days exceeds lookback_days; capping holding_period_days to lookback_days'
        )
        context.holding_period_days = context.lookback_days
      end

      context.filters_applied = {
        lookback_days: context.lookback_days,
        holding_period_days: context.holding_period_days,
        min_materiality_pct: context.min_materiality_pct,
        min_contract_value: context.min_contract_value,
        sizing_mode: context.sizing_mode,
        preferred_agencies: context.preferred_agencies
      }
    end

    def validate_equity!
      equity = context.total_equity
      stop_and_fail!('total_equity parameter is required and must be positive') if equity.nil? || equity <= 0
      equity
    end

    def validate_inputs
      stop_and_fail!('lookback_days must be positive') unless context.lookback_days.to_i.positive?
      stop_and_fail!('holding_period_days must be positive') unless context.holding_period_days.to_i.positive?
      stop_and_fail!('min_contract_value must be non-negative') if context.min_contract_value.to_f.negative?
      stop_and_fail!('min_materiality_pct must be non-negative') if context.min_materiality_pct.to_f.negative?

      allowed = %w[equal_weight materiality_weighted]
      stop_and_fail!("sizing_mode must be one of #{allowed.join(', ')}") unless allowed.include?(context.sizing_mode.to_s)
    end

    def fetch_recent_contracts
      start_date = context.lookback_days.to_i.days.ago.to_date
      end_date = Date.current

      # Fetch standard contracts by award_date AND QuarterlyTotal contracts by updated_at
      GovernmentContract.where(
        "(contract_type = 'QuarterlyTotal' AND updated_at >= ? AND updated_at <= ?) OR " \
        "(contract_type != 'QuarterlyTotal' AND award_date >= ? AND award_date <= ?)",
        start_date.beginning_of_day, end_date.end_of_day,
        start_date, end_date
      ).order(award_date: :desc)
    end

    def apply_filters(contracts)
      active_cutoff = context.holding_period_days.to_i.days.ago.to_date

      contracts.select do |contract|
        effective_date = if contract.contract_type == 'QuarterlyTotal'
                           contract.updated_at.to_date
                         else
                           contract.award_date
                         end

        next false if effective_date < active_cutoff
        next false if contract.contract_value.to_d < BigDecimal(context.min_contract_value.to_s)

        if context.preferred_agencies.present?
          next false unless context.preferred_agencies.include?(contract.agency)
        end

        threshold = threshold_for(contract.ticker)
        revenue = FundamentalDataService.get_annual_revenue(contract.ticker)
        materiality = MaterialityCalculator.calculate(contract_value: contract.contract_value, annual_revenue: revenue)

        if revenue.nil?
          Rails.logger.warn("[ContractsStrategy] Missing annual revenue for #{contract.ticker}; including contract by default")
          contract.define_singleton_method(:materiality_pct) { nil }
          true
        else
          contract.define_singleton_method(:materiality_pct) { materiality }
          materiality.to_f >= threshold.to_f
        end
      end
    end

    def threshold_for(ticker)
      sector = SectorClassifier.sector_for(ticker)
      (context.sector_thresholds[sector] || context.sector_thresholds[sector.to_sym] || context.min_materiality_pct).to_f
    end

    def build_weights(contracts)
      return {} if contracts.empty?

      grouped = contracts.group_by(&:ticker)

      case context.sizing_mode.to_s
      when 'materiality_weighted'
        grouped.transform_values do |rows|
          rows.sum do |c|
            val = c.respond_to?(:materiality_pct) ? c.materiality_pct : nil
            val.nil? ? 1.0 : val.to_f
          end
        end
      else
        grouped.transform_values { |_rows| 1.0 }
      end
    end

    def build_positions(weights, contracts, equity)
      return [] if weights.empty?

      total_weight = weights.values.sum
      return [] if total_weight.zero?

      contracts_by_ticker = contracts.group_by(&:ticker)

      weights.map do |ticker, weight|
        allocation_pct = (weight / total_weight) * 100
        target_value = equity * (allocation_pct / 100.0)

        most_recent = contracts_by_ticker[ticker].max_by(&:award_date)
        most_recent_date = if most_recent&.contract_type == 'QuarterlyTotal'
                             most_recent.updated_at.to_date
                           else
                             most_recent&.award_date
                           end

        TargetPosition.new(
          symbol: ticker,
          asset_type: :stock,
          target_value: target_value,
          details: {
            allocation_percent: allocation_pct.round(2),
            source: 'contracts',
            award_date: most_recent&.award_date,
            signal_date: most_recent_date,
            exit_date: most_recent_date&.+(context.holding_period_days.to_i),
            agency: most_recent&.agency,
            contract_value: contracts_by_ticker[ticker].sum(&:contract_value),
            materiality_pct: most_recent.respond_to?(:materiality_pct) ? most_recent.materiality_pct : nil
          }
        )
      end.sort_by { |pos| -pos.target_value }
    end
  end
end
