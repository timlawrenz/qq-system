# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

module TradingDashboard
  class FetchTradingDashboardSnapshot < GLCommand::Callable
    allows :strategy_name
    returns :metrics

    CACHE_KEY_PREFIX = 'trading_dashboard:snapshot:v1'
    CACHE_TTL = 30.seconds
    STALE_AFTER = 1.hour

    def call
      context.metrics = Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        build_metrics
      end
    rescue StandardError => e
      Rails.logger.error("TradingDashboard: failed to build metrics: #{e.class} - #{e.message}")
      stop_and_fail!('Failed to load trading dashboard')
    end

    private

    def cache_key
      strategy = context.strategy_name.to_s.strip
      strategy = 'default' if strategy.blank?

      "#{CACHE_KEY_PREFIX}:#{strategy}"
    end

    def build_metrics
      snapshot = latest_snapshot
      return empty_metrics if snapshot.nil?

      metadata = snapshot.metadata || {}
      account = metadata['account'] || {}
      positions = Array(metadata['positions'])
      top_positions = Array(metadata['top_positions']).presence ||
                      positions.sort_by { |p| -p.fetch('market_value', 0).to_d }.first(5)
      risk = metadata['risk'] || {}
      period = metadata['period'] || {}
      cashflows = metadata['cashflows'] || {}

      date_scope_start = cashflows['start_date'] || period['start_date']
      date_scope_end = cashflows['end_date'] || period['end_date'] || snapshot.snapshot_date&.to_s
      date_scope_source = cashflows['start_date'].present? ? 'cashflows.start_date' : 'period.start_date'

      captured_at = parse_time(metadata['snapshot_captured_at']) || snapshot.updated_at
      stale = captured_at.present? && captured_at < STALE_AFTER.ago

      current_equity = snapshot.total_equity&.to_d

      period_returns = calculate_period_returns(strategy_name: snapshot.strategy_name, end_date: snapshot.snapshot_date)

      peak_equity = PerformanceSnapshot.where(strategy_name: snapshot.strategy_name).maximum(:total_equity)&.to_d
      drawdown_from_peak_pct = if peak_equity.to_d.positive? && current_equity.to_d.positive?
                                 (((current_equity.to_d - peak_equity.to_d) / peak_equity.to_d) * 100).round(4)
                               end

      concentration_pct = risk['concentration_pct']&.to_d
      diversification_score = if concentration_pct
                                (100 - concentration_pct).round(2).to_f
                              else
                                positions.length.to_f
                              end

      {
        state: 'ok',
        strategy_name: snapshot.strategy_name,
        snapshot_date: snapshot.snapshot_date.to_s,
        snapshot_captured_at: captured_at&.iso8601,
        stale: stale,
        date_scope: {
          start_date: date_scope_start,
          end_date: date_scope_end,
          source: date_scope_source
        },
        equity: current_equity&.to_f,
        account: {
          cash: account['cash'],
          invested: account['invested'],
          cash_pct: account['cash_pct'],
          invested_pct: account['invested_pct'],
          position_count: account['position_count'] || positions.length
        },
        period_returns: period_returns,
        risk: {
          concentration_pct: risk['concentration_pct'],
          concentration_symbol: risk['concentration_symbol'],
          max_drawdown_pct: snapshot.max_drawdown_pct&.to_d&.to_f,
          drawdown_from_peak_pct: drawdown_from_peak_pct&.to_f,
          diversification_score: diversification_score
        },
        top_positions: top_positions,
        positions: positions
      }
    end

    def empty_metrics
      {
        state: 'empty',
        message: 'No performance snapshots found in the local database.',
        stale: true,
        equity: nil,
        account: {},
        period_returns: {},
        risk: {},
        top_positions: [],
        positions: []
      }
    end

    def latest_snapshot
      scope = PerformanceSnapshot.all
      scope = scope.where(strategy_name: context.strategy_name) if context.strategy_name.present?

      scope.order(snapshot_date: :desc, created_at: :desc).first
    end

    def calculate_period_returns(strategy_name:, end_date:)
      return {} if end_date.blank?

      end_date = Date.parse(end_date.to_s)

      starts = {
        today: end_date,
        wtd: end_date.beginning_of_week(:monday),
        mtd: end_date.beginning_of_month,
        ytd: end_date.beginning_of_year
      }

      starts.transform_values do |start_date|
        baseline = equity_on_or_after(strategy_name: strategy_name, start_date: start_date, end_date: end_date)
        latest = equity_on_or_after(strategy_name: strategy_name, start_date: end_date, end_date: end_date)

        next nil if baseline.nil? || latest.nil? || baseline.to_d.zero?

        delta = (latest.to_d - baseline.to_d).round(4)
        pct = ((delta / baseline.to_d) * 100).round(4)

        {
          start_date: start_date.to_s,
          end_date: end_date.to_s,
          start_equity: baseline.to_f,
          end_equity: latest.to_f,
          delta: delta.to_f,
          pct: pct.to_f
        }
      end
    end

    def equity_on_or_after(strategy_name:, start_date:, end_date:)
      PerformanceSnapshot
        .where(strategy_name: strategy_name, snapshot_date: start_date..end_date)
        .order(snapshot_date: :asc)
        .limit(1)
        .pick(:total_equity)
    end

    def parse_time(value)
      return value if value.is_a?(Time)
      return nil if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      Time.zone.parse(value.to_s)
    rescue StandardError
      nil
    end
  end
end

# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
