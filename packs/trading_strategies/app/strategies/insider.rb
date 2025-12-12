# frozen_string_literal: true

module TradingStrategies
  module Strategies
    class Insider < BaseStrategy
      def generate_signals(_context)
        lookback_days = config['lookback_days'] || 30
        min_value = config['min_transaction_value'] || 10_000
        executive_only = config['executive_only']
        
        trades = fetch_trades(lookback_days, min_value, executive_only)
        
        signals = []
        trades.group_by(&:ticker).each do |ticker, ticker_trades|
          score = calculate_score(ticker_trades)
          
          signals << TradingSignal.new(
            ticker: ticker,
            strategy_name: 'insider',
            score: score,
            metadata: { 
              trade_count: ticker_trades.count,
              total_value: ticker_trades.sum { |t| parse_value(t.trade_size_usd) }
            }
          )
        end
        
        signals
      end

      private

      def fetch_trades(lookback_days, min_value, executive_only)
        query = QuiverTrade
          .where(transaction_type: 'Purchase')
          .where(trader_source: 'insider')
          .where(transaction_date: lookback_days.days.ago..)

        if executive_only
          # Filter for C-suite titles
          query = query.where("relationship ILIKE ANY (array['%CEO%', '%CFO%', '%COO%', '%President%', '%Chairman%'])")
        end

        # Note: trade_size_usd is a string like "$10,000", so SQL filtering is hard.
        # We filter in memory for simplicity, though less efficient.
        query.to_a.select do |t|
          parse_value(t.trade_size_usd) >= min_value
        end
      end

      def calculate_score(ticker_trades)
        # Base score 0.6 for any insider buying meeting criteria
        score = 0.6
        
        # Boost for multiple insiders buying
        unique_insiders = ticker_trades.map(&:trader_name).uniq.count
        score += 0.2 if unique_insiders > 1
        
        # Boost for very large total value (> $100k)
        total_value = ticker_trades.sum { |t| parse_value(t.trade_size_usd) }
        score += 0.2 if total_value > 100_000
        
        [score, 1.0].min
      end

      def parse_value(value_str)
        return 0.0 if value_str.nil?
        value_str.gsub(/[$,]/, '').to_f
      end
    end
  end
end
