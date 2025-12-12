# frozen_string_literal: true

# GenerateLobbyingPortfolio Command
#
# Generates a market-neutral long/short portfolio based on corporate lobbying spend.
# This is Phase 2a - MVP version using absolute lobbying spend ranking.
#
# Strategy Logic:
# - Long: Top quintile (highest lobbying spenders = most political influence)
# - Short: Bottom quintile (lowest/no lobbying = least political influence)
# - Market-neutral: 50% long, 50% short
# - Equal-weight within each leg
#
# Academic Rationale:
# - High lobbying correlates with favorable political outcomes
# - Favorable outcomes correlate with stock returns (5.5-6.7% excess annual return)
# - Market-neutral structure captures relative performance
#
# Example Output:
#   Long positions (Q1): JNJ, MSFT
#   Short positions (Q5): LOW, TGT
#   Position size: $5,000 each
#
# Usage:
#   result = TradingStrategies::GenerateLobbyingPortfolio.call(
#     quarter: 'Q4 2025',
#     total_equity: 100000
#   )
module TradingStrategies
  class GenerateLobbyingPortfolio < GLCommand::Callable
    allows :quarter, :total_equity, :long_pct, :short_pct
    returns :target_positions, :long_tickers, :short_tickers, :skipped_tickers
    
    def call
      # Use current quarter if not specified
      context.quarter ||= current_quarter
      
      # Default to 50% long, 50% short (market-neutral)
      context.long_pct ||= 0.5
      context.short_pct ||= 0.5
      
      # Get current equity
      current_equity = context.total_equity || fetch_account_equity
      
      if current_equity <= 0
        Rails.logger.warn('GenerateLobbyingPortfolio: No equity available')
        context.target_positions = []
        context.long_tickers = []
        context.short_tickers = []
        context.skipped_tickers = []
        return context
      end
      
      # Get lobbying rankings
      service = LobbyingRankingService.new(quarter: context.quarter)
      quintiles = service.assign_quintiles
      
      if quintiles.empty?
        Rails.logger.warn("GenerateLobbyingPortfolio: No lobbying data for #{context.quarter}")
        context.target_positions = []
        context.long_tickers = []
        context.short_tickers = []
        context.skipped_tickers = []
        return context
      end
      
      # Separate into quintiles
      q1_tickers = quintiles.select { |_, q| q == 1 }.keys # Top 20% - LONG
      q5_tickers = quintiles.select { |_, q| q == 5 }.keys # Bottom 20% - SHORT
      
      # Calculate allocations
      long_allocation = current_equity * context.long_pct
      short_allocation = current_equity * context.short_pct
      
      # Equal weight within each leg
      long_weight_per_ticker = q1_tickers.any? ? long_allocation / q1_tickers.size : 0
      short_weight_per_ticker = q5_tickers.any? ? short_allocation / q5_tickers.size : 0
      
      # Build target positions
      positions = []
      skipped = []
      
      # Long positions (top quintile)
      q1_tickers.each do |ticker|
        if valid_ticker?(ticker)
          positions << TargetPosition.new(
            symbol: ticker,
            asset_type: :stock,
            target_value: long_weight_per_ticker
          )
        else
          skipped << ticker
        end
      end
      
      # Short positions (bottom quintile) - negative target value
      q5_tickers.each do |ticker|
        if valid_ticker?(ticker)
          positions << TargetPosition.new(
            symbol: ticker,
            asset_type: :stock,
            target_value: -short_weight_per_ticker # Negative for short
          )
        else
          skipped << ticker
        end
      end
      
      # Set context
      context.target_positions = positions
      context.long_tickers = q1_tickers - skipped
      context.short_tickers = q5_tickers - skipped
      context.skipped_tickers = skipped
      
      # Log summary
      Rails.logger.info(
        "GenerateLobbyingPortfolio: Generated portfolio for #{context.quarter} - " \
        "#{context.long_tickers.size} long, #{context.short_tickers.size} short, " \
        "#{context.skipped_tickers.size} skipped"
      )
      
      context
    end
    
    private
    
    def current_quarter
      date = Date.today
      quarter_num = ((date.month - 1) / 3) + 1
      "Q#{quarter_num} #{date.year}"
    end
    

    
    def valid_ticker?(ticker)
      # Basic validation - ticker should be uppercase alphanumeric
      ticker.present? && ticker.match?(/\A[A-Z]{1,5}\z/)
    end
  end
end
