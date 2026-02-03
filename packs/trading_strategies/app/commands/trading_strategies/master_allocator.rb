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
      config = load_and_merge_config
      validate_equity!

      strategies = initialize_strategies(config)
      all_signals, strategy_results = generate_all_signals(strategies)

      net_scores = net_signals(all_signals, config)

      # Prewarm market data cache so sizing can mostly use HistoricalBar instead
      # of calling Alpaca directly for each symbol.
      prewarm_market_data(net_scores)

      target_positions = size_positions(net_scores, config)

      build_result_context(target_positions, strategy_results, all_signals, net_scores, config)
    end

    private

    def load_and_merge_config
      environment = context.trading_mode || Rails.env
      config = load_config(environment)
      config = deep_merge(config, context.config_override) if context.config_override.present?
      config
    end

    def validate_equity!
      return unless context.total_equity.nil? || context.total_equity <= 0

      stop_and_fail!('total_equity parameter is required and must be positive')
    end

    def generate_all_signals(strategies)
      all_signals = []
      strategy_results = {}

      strategies.each do |strategy_name, strategy_instance|
        signals = strategy_instance.generate_signals({})
        Rails.logger.debug { "DEBUG: MasterAllocator: Strategy #{strategy_name} returned #{signals.size} signals" }
        all_signals.concat(signals)
        strategy_results[strategy_name] = { signal_count: signals.size, status: 'success' }
      rescue StandardError => e
        Rails.logger.error("MasterAllocator: Strategy #{strategy_name} failed: #{e.message}")
        strategy_results[strategy_name] = { error: e.message, status: 'failed' }
      end

      [all_signals, strategy_results]
    end

    def net_signals(all_signals, config)
      strategy_weights = extract_weights(config)
      netting_service = SignalNettingService.new(
        signals: all_signals,
        strategy_weights: strategy_weights
      )
      netting_service.call
    end

    def size_positions(net_results, config)
      risk_target_pct = config.dig('risk_management', 'target_risk_pct') || 0.01
      sizing_service = VolatilitySizingService.new(
        net_results: net_results,
        total_equity: context.total_equity,
        risk_target_pct: risk_target_pct
      )
      sizing_service.call
    end

    def prewarm_market_data(net_scores)
      all_symbols = net_scores.keys.map(&:to_s).uniq
      return if all_symbols.empty?

      # Only prewarm symbols that Alpaca's market data API can handle. This
      # matches the validation in FetchAlpacaData (A–Z, 1–5 chars).
      valid_symbols = all_symbols.grep(/\A[A-Z]{1,5}\z/)
      invalid_symbols = all_symbols - valid_symbols

      if invalid_symbols.any?
        Rails.logger.info(
          "MasterAllocator: Skipping #{invalid_symbols.size} symbols with invalid market-data tickers: " \
          "#{invalid_symbols.join(', ')}"
        )
      end

      return if valid_symbols.empty?

      atr_period = VolatilitySizingService::DEFAULT_ATR_PERIOD
      start_date = (atr_period + 5).days.ago.to_date
      end_date = Date.current

      Rails.logger.info(
        "MasterAllocator: Prewarming market data for #{valid_symbols.size} symbols from #{start_date} to #{end_date}"
      )

      fetch_result = Fetch.call(
        symbols: valid_symbols,
        start_date: start_date,
        end_date: end_date
      )

      if fetch_result.failure?
        Rails.logger.warn(
          "MasterAllocator: Market data prewarm failed: #{fetch_result.error&.message}"
        )
      elsif fetch_result.api_errors.present?
        Rails.logger.warn(
          "MasterAllocator: Market data prewarm had API errors: #{fetch_result.api_errors.join(', ')}"
        )
        Rails.logger.warn(
          'MasterAllocator: Using existing HistoricalBar cache only; ' \
          'ATR sizing may be based on stale or incomplete market data.'
        )
      end
    rescue StandardError => e
      Rails.logger.warn("MasterAllocator: Market data prewarm raised error: #{e.message}")
    end

    def build_result_context(target_positions, strategy_results, all_signals, net_scores, config)
      context.target_positions = target_positions
      context.strategy_results = strategy_results
      context.metadata = {
        total_signals: all_signals.size,
        netted_tickers: net_scores.size,
        generated_positions: target_positions.size,
        risk_target_pct: config.dig('risk_management', 'target_risk_pct') || 0.01
      }
    end

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

        # Try to find the class
        begin
          klass = "TradingStrategies::Strategies::#{name.camelize}".constantize
        rescue NameError
          # Fallback: try without top-level namespace if already inside
          # This handles cases where Rails autoloading behaves differently in tests
          begin
            klass = "Strategies::#{name.camelize}".constantize
          rescue NameError
            # Last resort: try to require the file manually
            # Note: 'name' is like 'congressional', file is 'congressional.rb'
            # Use File.join to construct path correctly
            require Rails.root.join("packs/trading_strategies/app/strategies/#{name}.rb")
            klass = "TradingStrategies::Strategies::#{name.camelize}".constantize
          end
        end

        instances[name] = klass.new(strategy_conf)
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
