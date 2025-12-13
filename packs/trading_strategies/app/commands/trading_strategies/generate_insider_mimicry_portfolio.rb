# frozen_string_literal: true

module TradingStrategies
  # Basic insider trading mimicry strategy
  # Mimics purchases by corporate insiders (CEO, CFO, Directors)
  # Focus on purchases only (higher signal strength)
  class GenerateInsiderMimicryPortfolio < GLCommand::Callable
    # Configuration options
    allows :lookback_days, :min_transaction_value, :executive_only,
           :position_size_weight_by_value, :total_equity, :max_positions

    # Returns
    returns :target_positions, :total_value, :filters_applied, :stats

    def call
      set_defaults
      validate_inputs

      context.filters_applied = build_filters_summary
      context.stats = {}

      equity = validate_equity!
      context.total_value = equity

      trades = fetch_recent_purchases
      context.stats[:total_trades] = trades.count

      filtered_trades = apply_filters(trades)
      context.stats[:trades_after_filters] = filtered_trades.count

      weighted_tickers = calculate_weighted_tickers(filtered_trades)
      context.stats[:unique_tickers] = weighted_tickers.count

      positions = create_target_positions(weighted_tickers, equity)
      context.target_positions = positions

      log_warnings_if_needed(positions)

      context
    end

    private

    def set_defaults
      context.lookback_days ||= 30
      context.min_transaction_value ||= 10_000
      context.executive_only = true if context.executive_only.nil?
      context.position_size_weight_by_value = true if context.position_size_weight_by_value.nil?
      context.max_positions ||= 20 # Limit to top 20 by weight
    end

    def validate_equity!
      equity = context.total_equity
      stop_and_fail!('total_equity parameter is required and must be positive') if equity.nil? || equity <= 0
      equity
    end

    def validate_inputs
      fail!('lookback_days must be positive') unless context.lookback_days.positive?
      fail!('min_transaction_value must be positive') unless context.min_transaction_value.positive?
    end

    def build_filters_summary
      {
        lookback_days: context.lookback_days,
        min_transaction_value: context.min_transaction_value,
        executive_only: context.executive_only
      }
    end

    def fetch_recent_purchases
      QuiverTrade
        .where(transaction_type: 'Purchase')
        .where(trader_source: 'insider')
        .where(transaction_date: context.lookback_days.days.ago..)
    end

    def apply_filters(trades)
      filtered = trades
      filtered = filter_by_transaction_value(filtered)
      filtered = filter_by_relationship(filtered) if context.executive_only
      filtered
    end

    def filter_by_transaction_value(trades)
      trades.select do |trade|
        value = parse_trade_value(trade.trade_size_usd)
        value && value >= context.min_transaction_value
      end
    end

    def filter_by_relationship(trades)
      executive_titles = %w[CEO CFO President Chief]

      trades.select do |trade|
        next false if trade.relationship.blank?

        executive_titles.any? { |title| trade.relationship.include?(title) }
      end
    end

    def calculate_weighted_tickers(trades)
      trades_by_ticker = trades.group_by(&:ticker)

      trades_by_ticker.transform_values do |ticker_trades|
        calculate_ticker_weight(ticker_trades)
      end
    end

    def calculate_ticker_weight(trades)
      if context.position_size_weight_by_value
        # Weight by total transaction value
        trades.sum { |t| parse_trade_value(t.trade_size_usd) || 0 }
      else
        # Equal weight per trade
        trades.count.to_f
      end
    end

    def create_target_positions(weighted_tickers, equity)
      return [] if weighted_tickers.empty?

      top_tickers = select_top_tickers(weighted_tickers)
      capped_tickers = cap_position_weights(top_tickers)
      capped_total_weight = capped_tickers.values.sum

      return [] if capped_total_weight.zero?

      generate_positions_from_weights(capped_tickers, capped_total_weight, equity, top_tickers)
    end

    def select_top_tickers(weighted_tickers)
      max_positions = context.max_positions || 20
      top_tickers = weighted_tickers.sort_by { |_, weight| -weight }.first(max_positions).to_h

      if weighted_tickers.size > top_tickers.size
        Rails.logger.info(
          "[InsiderStrategy] Limited to top #{top_tickers.size} of #{weighted_tickers.size} tickers by weight"
        )
      end

      context.stats[:tickers_before_limit] = weighted_tickers.size
      context.stats[:tickers_after_limit] = top_tickers.size
      top_tickers
    end

    def cap_position_weights(top_tickers)
      total_weight = top_tickers.values.sum
      return {} if total_weight.zero?

      max_position_weight = total_weight * 0.25
      top_tickers.transform_values do |weight|
        [weight, max_position_weight].min
      end
    end

    def generate_positions_from_weights(capped_tickers, capped_total_weight, equity, top_tickers)
      positions = capped_tickers.map do |ticker, weight|
        allocation_pct = (weight / capped_total_weight) * 100
        target_value = equity * (allocation_pct / 100.0)

        TargetPosition.new(
          symbol: ticker,
          asset_type: :stock,
          target_value: target_value,
          details: {
            allocation_percent: allocation_pct.round(2),
            source: 'insider',
            weight: weight,
            original_weight: top_tickers[ticker]
          }
        )
      end

      positions.sort_by { |pos| -pos.target_value }
    end

    def log_warnings_if_needed(positions)
      if positions.empty?
        Rails.logger.warn('[InsiderMimicryStrategy] No positions generated - no trades passed filters')
      elsif positions.count < 5
        message = "[InsiderMimicryStrategy] Only #{positions.count} positions generated - " \
                  'portfolio may be under-diversified'
        Rails.logger.warn(message)
      end
    end

    def parse_trade_value(value_string)
      return nil if value_string.blank?

      value_string.to_s.gsub(/[,$]/, '').to_f
    end
  end
end
