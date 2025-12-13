# frozen_string_literal: true

module TradingStrategies
  class GenerateBlendedPortfolio < GLCommand::Callable
    allows :trading_mode, :total_equity, :config_override

    returns :target_positions, :metadata, :strategy_results

    def call
      # Delegate to MasterAllocator (Unified Factor Model)
      result = MasterAllocator.call!(
        trading_mode: context.trading_mode,
        total_equity: context.total_equity,
        config_override: context.config_override
      )

      context.target_positions = result.target_positions
      context.strategy_results = result.strategy_results

      # Enrich metadata with exposure stats for backward compatibility
      context.metadata = result.metadata.merge(
        calculate_exposure_stats(result.target_positions, context.total_equity)
      )
    end

    private

    def calculate_exposure_stats(positions, equity)
      if positions.empty? || equity.zero?
        return { gross_exposure_pct: 0.0, net_exposure_pct: 0.0,
                 positions_capped: [] }
      end

      long_value = positions.select { |p| p.target_value.positive? }.sum(&:target_value)
      short_value = positions.select { |p| p.target_value.negative? }.sum(&:target_value)

      gross_value = long_value + short_value.abs
      net_value = long_value + short_value

      {
        gross_exposure_pct: (gross_value / equity).to_f,
        net_exposure_pct: (net_value / equity).to_f,
        positions_capped: [] # Placeholder as MasterAllocator handles sizing differently
      }
    end
  end
end
