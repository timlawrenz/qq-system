# frozen_string_literal: true

module TradingStrategies
  module Strategies
    class Lobbying < BaseStrategy
      def generate_signals(_context)
        quarter = config['quarter'] || 'current'
        
        service = LobbyingRankingService.new(quarter: quarter)
        quintiles = service.assign_quintiles
        rankings = service.rank_by_lobbying
        
        signals = []
        quintiles.each do |ticker, quintile|
          score = score_from_quintile(quintile)
          next if score.zero?
          
          spend = rankings[ticker][:spend]
          
          signals << TradingSignal.new(
            ticker: ticker,
            strategy_name: 'lobbying',
            score: score,
            metadata: { quintile: quintile, spend: spend }
          )
        end
        signals
      end
      
      private
      
      def score_from_quintile(quintile)
        case quintile
        when 1 then 1.0
        when 2 then 0.5
        when 3 then 0.0
        when 4 then -0.5
        when 5 then -1.0
        else 0.0
        end
      end
    end
  end
end
