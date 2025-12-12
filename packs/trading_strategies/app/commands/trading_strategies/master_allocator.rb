# frozen_string_literal: true

module TradingStrategies
  # Orchestrator for the Unified Factor Model
  # 1. Collects signals from all enabled strategies
  # 2. Nets them into a single conviction per ticker
  # 3. Sizes positions based on volatility (ATR)
  class MasterAllocator < GLCommand::Callable
    allows :total_equity, :config_override, :trading_mode

    returns :target_positions, :metadata, :strategy_results

    def call
      # 1. Load Configuration
      environment = context.trading_mode || Rails.env
      config = load_config(environment)
      
      if context.config_override.present?
        config = deep_merge(config, context.config_override)
      end

      equity = context.total_equity
      if equity.nil? || equity <= 0
        stop_and_fail!('total_equity parameter is required and must be positive')
      end

      # 2. Initialize Strategies
      strategies = initialize_strategies(config)
      
      # 3. Generate Signals
      all_signals = []
      strategy_results = {}
      
      strategies.each do |strategy_name, strategy_instance|
        begin
          signals = strategy_instance.generate_signals({})
          all_signals.concat(signals)
          strategy_results[strategy_name] = { signal_count: signals.size, status: 'success' }
        rescue StandardError => e
          Rails.logger.error("MasterAllocator: Strategy #{strategy_name} failed: #{e.message}")
          strategy_results[strategy_name] = { error: e.message, status: 'failed' }
        end
      end

      # 4. Net Signals
      strategy_weights = extract_weights(config)
      netting_service = SignalNettingService.new(
        signals: all_signals,
        strategy_weights: strategy_weights
      )
      net_scores = netting_service.call

      # 5. Size Positions
      risk_target_pct = config.dig('risk_management', 'target_risk_pct') || 0.01
      sizing_service = VolatilitySizingService.new(
        net_scores: net_scores,
        total_equity: equity,
        risk_target_pct: risk_target_pct
      )
      target_positions = sizing_service.call

      # 6. Return Results
      context.target_positions = target_positions
      context.strategy_results = strategy_results
      context.metadata = {
        total_signals: all_signals.size,
        netted_tickers: net_scores.size,
        generated_positions: target_positions.size,
        risk_target_pct: risk_target_pct
      }
    end

    private

    def load_config(environment)
      config_path = Rails.root.join('config/portfolio_strategies.yml')
      return {} unless File.exist?(config_path)
      
      all_configs = YAML.load_file(config_path)
      default_config = all_configs['default'] || {}
      env_config = all_configs[environment] || {}
      
      deep_merge(default_config, env_config)
    end

    def initialize_strategies(config)
      instances = {}
      strategies_config = config['strategies'] || {}
      
      strategies_config.each do |name, strategy_conf|
        next unless strategy_conf['enabled']
        
        # Convention: strategies are in TradingStrategies::Strategies namespace
        # e.g., "congressional" -> TradingStrategies::Strategies::Congressional
        class_name = "TradingStrategies::Strategies::#{name.camelize}"
        
        begin
          klass = class_name.constantize
          instances[name] = klass.new(strategy_conf)
        rescue NameError
          Rails.logger.warn("MasterAllocator: Strategy class #{class_name} not found")
        end
      end
      
      instances
    end

    def extract_weights(config)
      weights = {}
      strategies_config = config['strategies'] || {}
      
      strategies_config.each do |name, strategy_conf|
        next unless strategy_conf['enabled']
        weights[name] = strategy_conf['weight'] || 0.0
      end
      
      weights
    end

    def deep_merge(hash1, hash2)
      hash1.merge(hash2) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end
  end
end
