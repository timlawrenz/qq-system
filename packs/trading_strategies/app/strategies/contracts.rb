# frozen_string_literal: true

module TradingStrategies
  module Strategies
    class Contracts < BaseStrategy
      def generate_signals(_context)
        lookback_days = config['lookback_days'] || 7
        holding_days = config['holding_period_days'] || 5
        min_value = config['min_contract_value'] || 10_000_000
        min_materiality = config['min_materiality_pct'] || 1.0
        sector_thresholds = config['sector_thresholds'] || {}
        preferred_agencies = Array(config['preferred_agencies']).compact

        # Use the portfolio generator's filtering logic for consistency.
        result = TradingStrategies::GenerateContractsPortfolio.call(
          total_equity: 1.0, # dummy equity; we only need filtered set
          lookback_days: lookback_days,
          holding_period_days: holding_days,
          min_contract_value: min_value,
          min_materiality_pct: min_materiality,
          sector_thresholds: sector_thresholds,
          preferred_agencies: preferred_agencies,
          sizing_mode: 'materiality_weighted'
        )

        return [] unless result.success?

        result.target_positions.map do |pos|
          # Map allocation % (e.g. 1.5%) to a score.
          # Base score 0.5 + (allocation / 10.0).
          # Example: 1.0% alloc -> 0.6 score
          #          5.0% alloc -> 1.0 score
          alloc = pos.details[:allocation_percent].to_f
          raw_score = 0.5 + (alloc / 10.0)
          
          TradingSignal.new(
            ticker: pos.symbol,
            strategy_name: 'contracts',
            score: raw_score.clamp(0.5, 1.0),
            metadata: pos.details
          )
        end
      end
    end
  end
end

# Provide a top-level Contracts constant for Zeitwerk while keeping the namespaced version.
class Contracts < TradingStrategies::Strategies::Contracts; end
