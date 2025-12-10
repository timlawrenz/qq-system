# frozen_string_literal: true

# GenerateBlendedPortfolio Command
#
# GLCommand wrapper around BlendedPortfolioBuilder that combines multiple
# trading strategies into a single unified portfolio.
#
# This command:
# 1. Loads configuration from config/portfolio_strategies.yml
# 2. Executes enabled strategies with configured weights
# 3. Merges overlapping positions (consensus signals)
# 4. Applies risk controls
# 5. Returns unified portfolio ready for execution
#
# Usage:
#   # Use environment-specific configuration (paper/live)
#   result = TradingStrategies::GenerateBlendedPortfolio.call(
#     trading_mode: 'paper'
#   )
#
#   # Override configuration at runtime
#   result = TradingStrategies::GenerateBlendedPortfolio.call(
#     config_override: {
#       strategy_weights: { congressional: 0.7, lobbying: 0.3 }
#     }
#   )
#
#   # Specify custom equity
#   result = TradingStrategies::GenerateBlendedPortfolio.call(
#     total_equity: 50_000
#   )
module TradingStrategies
  class GenerateBlendedPortfolio < GLCommand::Callable
    allows :total_equity, :config_override, :trading_mode
    returns :target_positions, :metadata, :strategy_results, :config_used
    
    def call
      # Determine environment
      environment = context.trading_mode || Rails.env
      
      Rails.logger.info("GenerateBlendedPortfolio: Loading configuration for #{environment}")
      
      # Load configuration
      config = load_config(environment)
      
      # Apply overrides if provided
      if context.config_override.present?
        Rails.logger.info("GenerateBlendedPortfolio: Applying configuration overrides")
        config = deep_merge(config, context.config_override)
      end
      
      # Get equity
      equity = context.total_equity || fetch_account_equity
      
      if equity <= 0
        Rails.logger.warn('GenerateBlendedPortfolio: No equity available')
        context.target_positions = []
        context.metadata = {}
        context.strategy_results = {}
        context.config_used = config
        return context
      end
      
      Rails.logger.info("GenerateBlendedPortfolio: Building portfolio with $#{equity}")
      
      # Extract configuration
      strategy_weights = extract_strategy_weights(config)
      options = extract_options(config)
      
      # Build blended portfolio
      builder = BlendedPortfolioBuilder.new(
        total_equity: equity,
        strategy_weights: strategy_weights,
        options: options
      )
      
      result = builder.build
      
      # Set context
      context.target_positions = result[:target_positions]
      context.metadata = result[:metadata]
      context.strategy_results = result[:strategy_results]
      context.config_used = config
      
      # Log summary
      log_portfolio_summary
      
      context
    rescue StandardError => e
      Rails.logger.error("GenerateBlendedPortfolio: Failed: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      stop_and_fail!("Failed to generate blended portfolio: #{e.message}")
    end
    
    private
    
    def load_config(environment)
      config_path = Rails.root.join('config/portfolio_strategies.yml')
      
      unless File.exist?(config_path)
        raise "Configuration file not found: #{config_path}"
      end
      
      all_configs = YAML.load_file(config_path)
      
      # Get environment config (inherits from default)
      default_config = all_configs['default'] || {}
      env_config = all_configs[environment] || {}
      
      # Merge environment config with default
      deep_merge(default_config, env_config)
    end
    
    def extract_strategy_weights(config)
      weights = {}
      
      strategies = config['strategies'] || config[:strategies] || {}
      strategies.each do |name, strategy_config|
        strategy_name = name.to_sym
        
        # Skip disabled strategies
        enabled = strategy_config['enabled'] || strategy_config[:enabled]
        next unless enabled
        
        weight = strategy_config['weight'] || strategy_config[:weight] || 0.0
        weights[strategy_name] = weight if weight > 0
      end
      
      if weights.empty?
        raise "No enabled strategies with weight > 0 found in configuration"
      end
      
      weights
    end
    
    def extract_options(config)
      strategies = config['strategies'] || config[:strategies] || {}
      
      # Extract strategy-specific params
      strategy_params = {}
      strategies.each do |name, strategy_config|
        strategy_name = name.to_sym
        params = strategy_config['params'] || strategy_config[:params] || {}
        
        # Convert 'current' quarter to actual current quarter
        if strategy_name == :lobbying && params['quarter'] == 'current'
          params = params.dup
          params['quarter'] = current_quarter
        end
        
        strategy_params[strategy_name] = symbolize_keys(params)
      end
      
      {
        merge_strategy: (config['merge_strategy'] || config[:merge_strategy] || :additive).to_sym,
        max_position_pct: config['max_position_pct'] || config[:max_position_pct] || 0.15,
        min_position_value: config['min_position_value'] || config[:min_position_value] || 1000,
        enable_shorts: config.key?('enable_shorts') ? config['enable_shorts'] : (config.key?(:enable_shorts) ? config[:enable_shorts] : true),
        strategy_params: strategy_params
      }
    end
    
    def fetch_account_equity
      alpaca_service = AlpacaService.new
      alpaca_service.account_equity
    rescue StandardError => e
      Rails.logger.error("GenerateBlendedPortfolio: Failed to fetch equity: #{e.message}")
      0
    end
    
    def current_quarter
      date = Date.today
      quarter_num = ((date.month - 1) / 3) + 1
      "Q#{quarter_num} #{date.year}"
    end
    
    def log_portfolio_summary
      Rails.logger.info("GenerateBlendedPortfolio: Generated #{context.target_positions.size} positions")
      Rails.logger.info("GenerateBlendedPortfolio: Metadata: #{context.metadata.inspect}")
      
      # Log strategy contributions
      if context.metadata[:strategy_contributions].present?
        Rails.logger.info("GenerateBlendedPortfolio: Strategy contributions:")
        context.metadata[:strategy_contributions].each do |strategy, count|
          Rails.logger.info("  - #{strategy}: #{count} positions")
        end
      end
      
      # Log capped positions
      if context.metadata[:positions_capped].present?
        Rails.logger.warn(
          "GenerateBlendedPortfolio: #{context.metadata[:positions_capped].size} positions were capped: " \
          "#{context.metadata[:positions_capped].join(', ')}"
        )
      end
      
      # Log exposure
      Rails.logger.info(
        "GenerateBlendedPortfolio: Exposure - " \
        "Gross: #{(context.metadata[:gross_exposure_pct] * 100).round(1)}%, " \
        "Net: #{(context.metadata[:net_exposure_pct] * 100).round(1)}%"
      )
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
    
    def symbolize_keys(hash)
      hash.transform_keys(&:to_sym)
    end
  end
end
