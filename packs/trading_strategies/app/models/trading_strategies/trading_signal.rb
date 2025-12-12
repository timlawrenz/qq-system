# frozen_string_literal: true

module TradingStrategies
  # Standardized data structure for strategy outputs
  # Decouples the "what to do" (signal) from "how much to buy" (sizing)
  class TradingSignal
    attr_reader :ticker, :strategy_name, :score, :metadata, :timestamp

    # @param ticker [String] The stock symbol (e.g., "AAPL")
    # @param strategy_name [String] Name of the strategy generating the signal
    # @param score [Float] Normalized conviction score between -1.0 (Strong Sell) and +1.0 (Strong Buy)
    # @param metadata [Hash] Additional context (e.g., { source: "insider", confidence: 0.8 })
    # @param timestamp [Time] When the signal was generated
    def initialize(ticker:, strategy_name:, score:, metadata: {}, timestamp: Time.current)
      @ticker = ticker
      @strategy_name = strategy_name
      @score = validate_score(score)
      @metadata = metadata
      @timestamp = timestamp
    end

    private

    def validate_score(score)
      float_score = score.to_f
      unless float_score.between?(-1.0, 1.0)
        raise ArgumentError, "Score must be between -1.0 and 1.0, got #{score}"
      end
      float_score
    end
  end
end
