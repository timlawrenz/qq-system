# frozen_string_literal: true

module TradingStrategies
  # Service to aggregate multiple TradingSignal objects for the same ticker
  # into a single NetConviction score.
  class SignalNettingService
    # @param signals [Array<TradingStrategies::TradingSignal>]
    # @param strategy_weights [Hash<String, Float>] Map of strategy_name => weight
    def initialize(signals:, strategy_weights:)
      @signals = signals
      @strategy_weights = strategy_weights
    end

    # @return [Hash<String, Hash>] Map of ticker => { score:, signals: }
    def call
      grouped_signals = @signals.group_by(&:ticker)

      net_results = {}

      grouped_signals.each do |ticker, ticker_signals|
        score = calculate_net_score(ticker_signals)
        net_results[ticker] = { 
          score: score,
          signals: ticker_signals
        }
      end

      net_results
    end

    private

    def calculate_net_score(signals)
      total_weighted_score = 0.0
      total_weight = 0.0

      signals.each do |signal|
        weight = @strategy_weights[signal.strategy_name] || 0.0

        if weight.zero?
          Rails.logger.warn("SignalNettingService: Strategy '#{signal.strategy_name}' has 0 weight or is missing")
          next
        end

        total_weighted_score += (signal.score * weight)
        total_weight += weight
      end

      return 0.0 if total_weight.zero?

      # Normalize: Sum(Score * Weight) / Sum(Weights)
      # This ensures the result is always between -1.0 and 1.0
      total_weighted_score / total_weight
    end
  end
end