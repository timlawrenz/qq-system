# frozen_string_literal: true

module TradingStrategies
  # Enhanced congressional trading strategy with committee filtering,
  # quality scoring, consensus detection, and dynamic position sizing
  class GenerateEnhancedCongressionalPortfolio < GLCommand::Callable
    # Configuration options (can be overridden)
    allows :enable_committee_filter, :min_quality_score, :enable_consensus_boost,
           :min_politicians_for_consensus, :lookback_days, :quality_multiplier_weight,
           :consensus_multiplier_weight

    # Returns
    returns :target_positions, :total_value, :filters_applied, :stats

    def call
      # Set defaults for optional parameters
      context.enable_committee_filter = true if context.enable_committee_filter.nil?
      context.min_quality_score ||= 5.0
      context.enable_consensus_boost = true if context.enable_consensus_boost.nil?
      context.min_politicians_for_consensus ||= 2
      context.lookback_days ||= 45
      context.quality_multiplier_weight ||= 0.6
      context.consensus_multiplier_weight ||= 0.4

      validate_inputs

      context.filters_applied = build_filters_summary
      context.stats = {}

      # Step 1: Get account equity
      equity = fetch_account_equity
      context.total_value = equity

      # Step 2: Get recent congressional purchases
      trades = fetch_recent_purchases
      context.stats[:total_trades] = trades.count

      # Step 3: Apply filters
      filtered_trades = apply_filters(trades)
      context.stats[:trades_after_filters] = filtered_trades.count

      # Step 4: Group by ticker and calculate weights
      weighted_tickers = calculate_weighted_tickers(filtered_trades)
      context.stats[:unique_tickers] = weighted_tickers.count

      # Step 5: Normalize weights and create target positions
      positions = create_target_positions(weighted_tickers, equity)
      context.target_positions = positions

      # Step 6: Log warnings if portfolio too small
      log_warnings_if_needed(positions)

      context
    end

    private

    def validate_inputs
      fail!('min_quality_score must be between 0 and 10') unless context.min_quality_score.between?(0, 10)
      fail!('lookback_days must be positive') unless context.lookback_days.positive?
    end

    def build_filters_summary
      {
        committee_filter: context.enable_committee_filter,
        min_quality_score: context.min_quality_score,
        consensus_boost: context.enable_consensus_boost,
        lookback_days: context.lookback_days
      }
    end

    def fetch_account_equity
      alpaca_service = AlpacaService.new
      alpaca_service.account_equity
    end

    def fetch_recent_purchases
      QuiverTrade
        .where(transaction_type: 'Purchase')
        .where(trader_source: 'congress')
        .where(transaction_date: context.lookback_days.days.ago..)
    end

    def apply_filters(trades)
      filtered = trades

      # Filter 1: Committee oversight (if enabled)
      filtered = filter_by_committee_oversight(filtered) if context.enable_committee_filter

      # Filter 2: Politician quality score
      filter_by_quality_score(filtered)
    end

    def filter_by_committee_oversight(trades)
      # Group trades by ticker, then check each
      trades_by_ticker = trades.group_by(&:ticker)

      passing_tickers = trades_by_ticker.select do |ticker, ticker_trades|
        has_committee_oversight?(ticker, ticker_trades)
      end.keys

      trades.where(ticker: passing_tickers)
    end

    def has_committee_oversight?(ticker, ticker_trades)
      # Classify stock to industries
      industries = Industry.classify_stock(ticker)
      return true if industries.empty? # Unknown stocks pass through

      industry_names = industries.map(&:name)

      # Check if any politician trading this stock has committee oversight
      trader_names = ticker_trades.map(&:trader_name).uniq

      trader_names.any? do |trader_name|
        politician = PoliticianProfile.find_by(name: trader_name)
        next false unless politician

        politician.has_committee_oversight?(industry_names)
      end
    end

    def filter_by_quality_score(trades)
      # Get all politician profiles with their quality scores
      profiles = PoliticianProfile.where(quality_score: context.min_quality_score..)
      passing_names = profiles.pluck(:name)

      # If no profiles meet threshold, relax it
      if passing_names.empty?
        Rails.logger.warn "No politicians meet quality threshold #{context.min_quality_score}, using all"
        return trades
      end

      trades.where(trader_name: passing_names)
    end

    def calculate_weighted_tickers(trades)
      # Group by ticker
      trades_by_ticker = trades.group_by(&:ticker)

      weighted = {}

      trades_by_ticker.each do |ticker, ticker_trades|
        # Calculate base weight (number of unique politicians)
        unique_politicians = ticker_trades.map(&:trader_name).uniq.count
        base_weight = unique_politicians.to_f

        # Apply quality multiplier
        quality_mult = calculate_quality_multiplier(ticker_trades)

        # Apply consensus multiplier (if enabled)
        consensus_mult = if context.enable_consensus_boost
                           calculate_consensus_multiplier(ticker)
                         else
                           1.0
                         end

        # Combined weight
        total_weight = base_weight * quality_mult * consensus_mult

        weighted[ticker] = {
          weight: total_weight,
          politician_count: unique_politicians,
          quality_multiplier: quality_mult,
          consensus_multiplier: consensus_mult
        }
      end

      weighted
    end

    def calculate_quality_multiplier(ticker_trades)
      trader_names = ticker_trades.map(&:trader_name).uniq
      profiles = PoliticianProfile.where(name: trader_names).with_quality_score

      return 1.0 if profiles.empty?

      avg_quality = profiles.average(:quality_score).to_f

      # Quality multiplier: score 5.0 = 1.0x, score 10.0 = 2.0x
      multiplier = 1.0 + ((avg_quality - 5.0) / 5.0)
      [multiplier, 0.5].max # Minimum 0.5x even for low quality
    end

    def calculate_consensus_multiplier(ticker)
      detector = ConsensusDetector.new(ticker: ticker, lookback_days: context.lookback_days)
      result = detector.call

      return 1.0 unless result[:is_consensus]

      # Consensus multiplier: 1.3x for 2 politicians, up to 2.0x for 3+
      1.0 + (result[:consensus_strength] * 0.3)
    end

    def create_target_positions(weighted_tickers, equity)
      return [] if weighted_tickers.empty?

      # Normalize weights to sum to 1.0
      total_weight = weighted_tickers.values.sum { |v| v[:weight] }

      weighted_tickers.map do |ticker, data|
        normalized_weight = data[:weight] / total_weight
        target_value = equity * normalized_weight

        TargetPosition.new(
          symbol: ticker,
          asset_type: :stock,
          target_value: target_value.round(2),
          details: {
            weight: normalized_weight.round(4),
            politician_count: data[:politician_count],
            quality_multiplier: data[:quality_multiplier].round(2),
            consensus_multiplier: data[:consensus_multiplier].round(2)
          }
        )
      end
    end

    def log_warnings_if_needed(positions)
      if positions.count < 3
        Rails.logger.warn "Enhanced strategy generated only #{positions.count} positions (< 3), insufficient diversification"
      end

      return unless positions.empty?

      Rails.logger.error "Enhanced strategy generated 0 positions! Filters may be too strict. Filters: #{context.filters_applied.inspect}"
    end
  end
end
