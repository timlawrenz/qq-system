# frozen_string_literal: true

module TradingStrategies
  module Strategies
    class Lobbying < BaseStrategy
      def generate_signals(_context)
        quarter = config['quarter'] || 'current'
        
        if quarter == 'current'
          # Lobbying data has a lag. 'Current' usually means the most recently completed quarter
          # or the one before that if we are in the filing period.
          # For now, let's assume we want the previous calendar quarter.
          current_date = Date.current
          prev_quarter_date = current_date.beginning_of_quarter - 1.day
          q_num = (prev_quarter_date.month - 1) / 3 + 1
          quarter = "Q#{q_num} #{prev_quarter_date.year}"
        end

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

# Provide a top-level Lobbying constant for Zeitwerk while keeping the namespaced version.
class Lobbying < TradingStrategies::Strategies::Lobbying; end
