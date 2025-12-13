# frozen_string_literal: true

module TradingStrategies
  module Strategies
    # Abstract base class for all trading strategies
    # Enforces the implementation of generate_signals
    class BaseStrategy
      attr_reader :config

      def initialize(config = {})
        @config = config
      end

      # @param context [Hash] Shared context (e.g., current_date, portfolio_state)
      # @return [Array<TradingStrategies::TradingSignal>]
      def generate_signals(_context)
        raise NotImplementedError, "#{self.class.name} must implement #generate_signals"
      end
    end
  end
end

# Provide a top-level BaseStrategy constant for Zeitwerk while keeping the namespaced version.
class BaseStrategy < TradingStrategies::Strategies::BaseStrategy; end
