# frozen_string_literal: true

# StrategyRegistry
#
# Central registry of available trading strategies.
# Provides metadata and execution interface for each strategy.
#
# Usage:
#   # List available strategies
#   StrategyRegistry.list_available
#
#   # Build a specific strategy
#   result = StrategyRegistry.build_strategy(
#     :congressional,
#     allocated_equity: 50_000,
#     params: { min_quality_score: 4.0 }
#   )
class StrategyRegistry
  STRATEGIES = {
    congressional: {
      command: 'TradingStrategies::GenerateEnhancedCongressionalPortfolio',
      params: %i[
        enable_committee_filter
        min_quality_score
        enable_consensus_boost
        lookback_days
        total_equity
      ],
      default_weight: 0.50,
      rebalance_frequency: :daily,
      description: 'Congressional trading signals with committee relevance and quality scoring'
    },
    lobbying: {
      command: 'TradingStrategies::GenerateLobbyingPortfolio',
      params: %i[
        quarter
        total_equity
        long_pct
        short_pct
      ],
      default_weight: 0.30,
      rebalance_frequency: :quarterly,
      description: 'Corporate lobbying influence factor (simplified, by absolute spend)'
    },
    insider: {
      command: 'TradingStrategies::GenerateInsiderMimicryPortfolio',
      params: %i[
        lookback_days
        min_transaction_value
        executive_only
        position_size_weight_by_value
        total_equity
      ],
      default_weight: 0.20,
      rebalance_frequency: :daily,
      description: 'Corporate insider trading mimicry (CEO/CFO purchases from SEC Form 4)'
    }
    # Future strategies register here:
    # committee_focused: {
    #   command: 'TradingStrategies::GenerateCommitteeFocusedPortfolio',
    #   params: [:total_equity, :min_committee_relevance],
    #   default_weight: 0.20,
    #   rebalance_frequency: :daily,
    #   description: 'Committee membership relevance weighting'
    # }
  }.freeze

  class << self
    # Build a strategy with given parameters
    #
    # @param name [Symbol] Strategy name (e.g., :congressional)
    # @param allocated_equity [Float] Equity allocated to this strategy
    # @param params [Hash] Additional parameters for the strategy
    # @return [GLCommand::Context] Result from strategy execution
    def build_strategy(name, allocated_equity:, params: {})
      strategy_config = STRATEGIES[name]

      raise ArgumentError, "Unknown strategy: #{name}. Available: #{STRATEGIES.keys.join(', ')}" unless strategy_config

      # Get command class
      command_class = strategy_config[:command].constantize

      # Merge allocated_equity with user params
      strategy_params = params.merge(total_equity: allocated_equity)

      # Execute strategy
      Rails.logger.info("StrategyRegistry: Building #{name} strategy with equity: $#{allocated_equity}")
      command_class.call(**strategy_params)
    rescue NameError
      Rails.logger.error("StrategyRegistry: Strategy command not found: #{strategy_config[:command]}")
      raise ArgumentError, "Strategy command not found: #{strategy_config[:command]}"
    rescue StandardError => e
      Rails.logger.error("StrategyRegistry: Failed to build #{name} strategy: #{e.message}")
      raise
    end

    # List all available strategies
    #
    # @return [Array<Hash>] Array of strategy metadata
    def list_available
      STRATEGIES.map do |name, config|
        {
          name: name,
          description: config[:description],
          default_weight: config[:default_weight],
          rebalance_frequency: config[:rebalance_frequency],
          params: config[:params]
        }
      end
    end

    # Check if strategy is registered
    #
    # @param name [Symbol] Strategy name
    # @return [Boolean]
    def registered?(name)
      STRATEGIES.key?(name)
    end

    # Get strategy configuration
    #
    # @param name [Symbol] Strategy name
    # @return [Hash] Strategy configuration
    def get_config(name)
      STRATEGIES[name]
    end

    # Get default weight for strategy
    #
    # @param name [Symbol] Strategy name
    # @return [Float] Default weight (0.0 to 1.0)
    def default_weight(name)
      STRATEGIES.dig(name, :default_weight) || 0.0
    end
  end
end
