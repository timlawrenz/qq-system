# frozen_string_literal: true

# TargetPosition PORO
#
# A Plain Old Ruby Object that serves as a stable data contract between
# the strategy and execution layers of the trading logic.
#
# This class represents a target position that a strategy wants to achieve,
# containing information about the symbol, asset type, target value, and
# additional details for future extensions.
class TargetPosition
  attr_reader :symbol, :asset_type, :target_value, :details

  # Initialize a new TargetPosition
  #
  # @param symbol [String] The trading symbol (e.g., "AAPL")
  # @param asset_type [Symbol] The type of asset (e.g., :stock)
  # @param target_value [Decimal] The target notional value for this position
  # @param details [Hash] Additional details for future use (e.g., option strike prices)
  def initialize(symbol:, asset_type:, target_value:, details: {})
    @symbol = symbol
    @asset_type = asset_type
    @target_value = target_value
    @details = details
  end

  # Equality comparison based on all attributes
  def ==(other)
    return false unless other.is_a?(TargetPosition)

    symbol == other.symbol &&
      asset_type == other.asset_type &&
      target_value == other.target_value &&
      details == other.details
  end

  # Hash representation for debugging and logging
  def to_h
    {
      symbol: symbol,
      asset_type: asset_type,
      target_value: target_value,
      details: details
    }
  end
end
