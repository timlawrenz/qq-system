# frozen_string_literal: true

# GenerateTargetPortfolio Command
#
# This command implements the "Simple" strategy which generates a target portfolio
# based on recent congressional trades and current account equity.
#
# Responsibilities:
# 1. Query QuiverTrade for "Purchase" transactions within the last 45 days
# 2. Call AlpacaService to get the current total account equity
# 3. Calculate equal-weight dollar value for each unique ticker
# 4. Return an array of TargetPosition instances
module TradingStrategies
  class GenerateTargetPortfolio < GLCommand::Callable
    allows :total_equity, :date
    returns :target_positions

    def call
      simulation_date = context.date || Time.current
      unique_tickers = fetch_unique_purchase_tickers(date: simulation_date)

      # Get equity (must be provided)
      current_equity = context.total_equity

      if current_equity.nil? || current_equity <= 0
        stop_and_fail!('total_equity parameter is required and must be positive')
      end

      # If no tickers, return empty portfolio
      if unique_tickers.empty?
        context.target_positions = []
        return context
      end

      # Calculate equal weight allocation for each ticker
      allocation_per_ticker = current_equity / unique_tickers.size

      context.target_positions = unique_tickers.map do |ticker|
        TargetPosition.new(
          symbol: ticker,
          asset_type: :stock,
          target_value: allocation_per_ticker
        )
      end
      context
    end

    private

    def fetch_unique_purchase_tickers(date: Time.current)
      tickers = QuiverTrade.purchases
                           .recent(45, date: date)
                           .distinct
                           .pluck(:ticker)
                           .compact_blank
                           .uniq

      # Filter out blocked assets
      blocked_symbols = BlockedAsset.blocked_symbols
      if blocked_symbols.any?
        filtered = tickers - blocked_symbols
        if filtered.size != tickers.size
          Rails.logger.info("Filtered #{blocked_symbols.size} blocked assets from target portfolio")
        end
        filtered
      else
        tickers
      end
    end
  end
end
