# frozen_string_literal: true

# PositionMerger
#
# Intelligently merges overlapping positions from multiple strategies.
# Handles consensus signals (stock appears in multiple strategies) by combining
# target values and tracking metadata about strategy contributions.
#
# Merge Strategies:
# - :additive - Sum target values (consensus = stronger signal)
# - :max - Take maximum value (no double-counting)
# - :average - Average target values (conservative)
#
# Usage:
#   merger = PositionMerger.new(
#     merge_strategy: :additive,
#     max_position_pct: 0.15,
#     total_equity: 100_000
#   )
#
#   positions = [
#     TargetPosition.new(symbol: 'AAPL', target_value: 10000, metadata: { source: :congressional }),
#     TargetPosition.new(symbol: 'AAPL', target_value: 8000, metadata: { source: :lobbying })
#   ]
#
#   merged = merger.merge(positions)
#   # => [TargetPosition(symbol: 'AAPL', target_value: 15000, metadata: { sources: [:congressional, :lobbying], ... })]
class PositionMerger
  attr_reader :merge_strategy, :max_position_pct, :total_equity, :min_position_value
  
  def initialize(options = {})
    @merge_strategy = options[:merge_strategy] || :additive
    @max_position_pct = options[:max_position_pct] || 0.15
    @total_equity = options[:total_equity] || 0
    @min_position_value = options[:min_position_value] || 1000
    
    validate_options!
  end
  
  # Merge array of TargetPosition objects
  # Returns array of merged TargetPosition objects with metadata
  #
  # @param positions [Array<TargetPosition>] Positions to merge
  # @return [Array<TargetPosition>] Merged positions
  def merge(positions)
    return [] if positions.empty?
    
    # Group positions by symbol
    grouped = positions.group_by(&:symbol)
    
    # Merge each group
    merged_positions = grouped.map do |symbol, symbol_positions|
      merge_symbol_positions(symbol, symbol_positions)
    end
    
    # Filter out positions below minimum
    merged_positions.select { |p| p.target_value.abs >= @min_position_value }
  end
  
  private
  
  def merge_symbol_positions(symbol, positions)
    # Calculate merged value based on strategy
    merged_value = calculate_merged_value(positions)
    
    # Apply position cap
    capped_value = apply_position_cap(merged_value)
    
    # Build details (metadata)
    details = build_metadata(positions, merged_value, capped_value)
    
    # Create merged position
    TargetPosition.new(
      symbol: symbol,
      asset_type: positions.first.asset_type,
      target_value: capped_value,
      details: details
    )
  end
  
  def calculate_merged_value(positions)
    case @merge_strategy
    when :additive
      # Sum all target values (consensus = stronger signal)
      positions.sum(&:target_value)
      
    when :max
      # Take maximum absolute value, preserve sign
      max_abs = positions.map { |p| p.target_value.abs }.max
      # Find position with max absolute value to get correct sign
      max_position = positions.max_by { |p| p.target_value.abs }
      max_position.target_value <=> 0 >= 0 ? max_abs : -max_abs
      
    when :average
      # Average target values
      positions.sum(&:target_value) / positions.size.to_f
      
    else
      raise ArgumentError, "Unknown merge strategy: #{@merge_strategy}"
    end
  end
  
  def apply_position_cap(value)
    return value if @total_equity <= 0
    
    max_value = @total_equity * @max_position_pct
    
    # Cap absolute value, preserve sign
    if value.abs > max_value
      value <=> 0 >= 0 ? max_value : -max_value
    else
      value
    end
  end
  
  def build_metadata(positions, original_value, capped_value)
    # Extract sources from position details
    sources = positions.map do |p|
      p.details&.dig(:source) || p.details&.dig('source')
    end.compact.uniq
    
    # Build details hash
    {
      sources: sources,
      consensus_count: positions.size,
      original_values: positions.map(&:target_value),
      original_total: original_value,
      was_capped: (original_value.abs != capped_value.abs),
      merge_strategy: @merge_strategy
    }
  end
  
  def validate_options!
    unless [:additive, :max, :average].include?(@merge_strategy)
      raise ArgumentError, "merge_strategy must be :additive, :max, or :average"
    end
    
    if @max_position_pct <= 0 || @max_position_pct > 1
      raise ArgumentError, "max_position_pct must be between 0 and 1"
    end
    
    if @min_position_value < 0
      raise ArgumentError, "min_position_value must be non-negative"
    end
  end
end
