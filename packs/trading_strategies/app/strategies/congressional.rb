# frozen_string_literal: true

module TradingStrategies
  module Strategies
    class Congressional < BaseStrategy
      def generate_signals(_context)
        lookback_days = config['lookback_days'] || 45
        min_quality = config['min_quality_score'] || 4.0
        
        trades = fetch_recent_purchases(lookback_days)
        
        # Filter by quality
        trades = filter_by_quality_score(trades, min_quality)
        
        # Group by ticker
        trades_by_ticker = trades.group_by(&:ticker)
        
        signals = []
        trades_by_ticker.each do |ticker, ticker_trades|
          score = calculate_score(ticker, ticker_trades)
          
          signals << TradingSignal.new(
            ticker: ticker,
            strategy_name: 'congressional',
            score: score,
            metadata: { 
              trade_count: ticker_trades.count,
              politicians: ticker_trades.map(&:trader_name).uniq
            }
          )
        end
        
        signals
      end

      private

      def fetch_recent_purchases(lookback_days)
        QuiverTrade
          .where(transaction_type: 'Purchase')
          .where(trader_source: 'congress')
          .where(transaction_date: lookback_days.days.ago..)
      end

      def filter_by_quality_score(trades, min_quality)
        profiles = PoliticianProfile.where(quality_score: min_quality..)
        passing_names = profiles.pluck(:name)

        if passing_names.empty?
          # Fallback if no politicians meet strict criteria
          return trades
        end

        trades.where(trader_name: passing_names)
      end

      def calculate_score(ticker, ticker_trades)
        # Base score on number of unique politicians buying
        unique_politicians = ticker_trades.map(&:trader_name).uniq.count
        
        # 1 politician = 0.5 (Moderate Buy)
        # 2 politicians = 0.8 (Strong Buy)
        # 3+ politicians = 1.0 (Max Conviction)
        base_score = case unique_politicians
                     when 1 then 0.5
                     when 2 then 0.8
                     else 1.0
                     end
        
        # Boost by quality
        quality_mult = calculate_quality_multiplier(ticker_trades)
        
        # Final score capped at 1.0
        [base_score * quality_mult, 1.0].min
      end

      def calculate_quality_multiplier(ticker_trades)
        trader_names = ticker_trades.map(&:trader_name).uniq
        profiles = PoliticianProfile.where(name: trader_names).with_quality_score

        return 1.0 if profiles.empty?

        avg_quality = profiles.average(:quality_score).to_f
        
        # Boost if average quality is high (> 7.0)
        # 7.0 -> 1.0x
        # 10.0 -> 1.3x
        if avg_quality > 7.0
          1.0 + ((avg_quality - 7.0) / 10.0)
        else
          1.0
        end
      end
    end
  end
end
