# frozen_string_literal: true

# BlendedPortfolioBuilder
#
# Orchestrates multiple trading strategies and combines their outputs into
# a single unified portfolio with risk controls.
#
# This is the core component of the multi-strategy system. It:
# 1. Executes each enabled strategy with its allocated equity
# 2. Collects all target positions
# 3. Merges overlapping positions (consensus signals)
# 4. Applies risk controls (position limits, sector limits)
# 5. Returns final blended portfolio with metadata
#
# Usage:
#   builder = BlendedPortfolioBuilder.new(
#     total_equity: 100_000,
#     strategy_weights: {
#       congressional: 0.50,
#       lobbying: 0.30
#     },
#     options: {
#       merge_strategy: :additive,
#       max_position_pct: 0.15,
#       min_position_value: 1000,
#       enable_shorts: true
#     }
#   )
#
#   result = builder.build
#   # => {
#   #   target_positions: [TargetPosition, ...],
#   #   metadata: { ... },
#   #   strategy_results: { congressional: { ... }, lobbying: { ... } }
#   # }
class BlendedPortfolioBuilder
  attr_reader :total_equity, :strategy_weights, :options
  
  def initialize(total_equity:, strategy_weights:, options: {})
    @total_equity = total_equity
    @strategy_weights = strategy_weights
    @options = default_options.merge(options)
    
    validate_inputs!
  end
  
  # Build blended portfolio by executing all strategies
  #
  # @return [Hash] Blended portfolio with metadata
  def build
    Rails.logger.info("BlendedPortfolioBuilder: Building portfolio with $#{@total_equity} equity")
    Rails.logger.info("BlendedPortfolioBuilder: Strategy weights: #{@strategy_weights.inspect}")
    
    # Execute all strategies
    strategy_results = execute_strategies
    
    # Collect all positions
    all_positions = collect_positions(strategy_results)
    
    # Merge overlapping positions
    merged_positions = merge_positions(all_positions)
    
    # Apply risk controls
    final_positions = apply_risk_controls(merged_positions)
    
    # Calculate metadata
    metadata = calculate_metadata(final_positions, strategy_results)
    
    Rails.logger.info("BlendedPortfolioBuilder: Generated #{final_positions.size} positions")
    
    {
      target_positions: final_positions,
      metadata: metadata,
      strategy_results: strategy_results
    }
  end
  
  private
  
  def default_options
    {
      merge_strategy: :additive,
      max_position_pct: 0.15,
      min_position_value: 1000,
      enable_shorts: true,
      strategy_params: {}  # Strategy-specific parameters
    }
  end
  
  def validate_inputs!
    if @total_equity <= 0
      raise ArgumentError, "total_equity must be positive"
    end
    
    if @strategy_weights.empty?
      raise ArgumentError, "strategy_weights cannot be empty"
    end
    
    # Validate all strategies are registered
    @strategy_weights.keys.each do |strategy_name|
      unless StrategyRegistry.registered?(strategy_name)
        raise ArgumentError, "Unknown strategy: #{strategy_name}"
      end
    end
    
    # Weights should sum to approximately 1.0 (allow small rounding errors)
    weight_sum = @strategy_weights.values.sum
    unless (weight_sum - 1.0).abs < 0.01
      Rails.logger.warn("BlendedPortfolioBuilder: Strategy weights sum to #{weight_sum}, not 1.0")
    end
  end
  
  def execute_strategies
    results = {}
    
    @strategy_weights.each do |strategy_name, weight|
      next if weight <= 0
      
      allocated_equity = @total_equity * weight
      
      Rails.logger.info("BlendedPortfolioBuilder: Executing #{strategy_name} with $#{allocated_equity.round(2)}")
      
      begin
        # Get strategy-specific params
        strategy_params = @options.dig(:strategy_params, strategy_name) || {}
        
        # Build strategy
        result = StrategyRegistry.build_strategy(
          strategy_name,
          allocated_equity: allocated_equity,
          params: strategy_params
        )
        
        if result.success?
          results[strategy_name] = {
            success: true,
            positions: result.target_positions || [],
            allocated_equity: allocated_equity,
            weight: weight
          }
          
          Rails.logger.info(
            "BlendedPortfolioBuilder: #{strategy_name} generated #{result.target_positions.size} positions"
          )
        else
          results[strategy_name] = {
            success: false,
            error: result.error,
            positions: [],
            allocated_equity: allocated_equity,
            weight: weight
          }
          
          Rails.logger.error(
            "BlendedPortfolioBuilder: #{strategy_name} failed: #{result.error}"
          )
        end
        
      rescue StandardError => e
        results[strategy_name] = {
          success: false,
          error: e.message,
          positions: [],
          allocated_equity: allocated_equity,
          weight: weight
        }
        
        Rails.logger.error(
          "BlendedPortfolioBuilder: #{strategy_name} crashed: #{e.message}"
        )
      end
    end
    
    results
  end
  
  def collect_positions(strategy_results)
    all_positions = []
    
    strategy_results.each do |strategy_name, result|
      next unless result[:success]
      
      # Tag each position with its source strategy
      result[:positions].each do |position|
        # Add source to details (create new position with updated details)
        updated_details = (position.details || {}).merge(source: strategy_name)
        
        tagged_position = TargetPosition.new(
          symbol: position.symbol,
          asset_type: position.asset_type,
          target_value: position.target_value,
          details: updated_details
        )
        
        all_positions << tagged_position
      end
    end
    
    all_positions
  end
  
  def merge_positions(positions)
    merger = PositionMerger.new(
      merge_strategy: @options[:merge_strategy],
      max_position_pct: @options[:max_position_pct],
      total_equity: @total_equity,
      min_position_value: @options[:min_position_value]
    )
    
    merged = merger.merge(positions)
    
    Rails.logger.info(
      "BlendedPortfolioBuilder: Merged #{positions.size} positions into #{merged.size} final positions"
    )
    
    merged
  end
  
  def apply_risk_controls(positions)
    controlled_positions = positions
    
    # Filter shorts if disabled
    unless @options[:enable_shorts]
      controlled_positions = controlled_positions.select { |p| p.target_value >= 0 }
      Rails.logger.info("BlendedPortfolioBuilder: Filtered short positions (shorts disabled)")
    end
    
    # Future: Add sector limits here
    # Future: Add correlation limits here
    
    controlled_positions
  end
  
  def calculate_metadata(positions, strategy_results)
    # Calculate exposure metrics
    long_exposure = positions.select { |p| p.target_value > 0 }.sum(&:target_value)
    short_exposure = positions.select { |p| p.target_value < 0 }.sum { |p| p.target_value.abs }
    gross_exposure = long_exposure + short_exposure
    net_exposure = long_exposure - short_exposure
    
    # Count strategy contributions
    strategy_contributions = {}
    positions.each do |pos|
      sources = pos.details&.dig(:sources) || []
      sources.each do |source|
        strategy_contributions[source] ||= 0
        strategy_contributions[source] += 1
      end
    end
    
    # Find capped positions
    positions_capped = positions.select { |p| p.details&.dig(:was_capped) }.map(&:symbol)
    
    # Count successful/failed strategies
    successful_strategies = strategy_results.count { |_, r| r[:success] }
    failed_strategies = strategy_results.count { |_, r| !r[:success] }
    
    {
      total_positions: positions.size,
      long_positions: positions.count { |p| p.target_value > 0 },
      short_positions: positions.count { |p| p.target_value < 0 },
      long_exposure: long_exposure,
      short_exposure: short_exposure,
      gross_exposure: gross_exposure,
      net_exposure: net_exposure,
      gross_exposure_pct: gross_exposure / @total_equity,
      net_exposure_pct: net_exposure / @total_equity,
      strategy_contributions: strategy_contributions,
      positions_capped: positions_capped,
      successful_strategies: successful_strategies,
      failed_strategies: failed_strategies,
      merge_strategy: @options[:merge_strategy]
    }
  end
end
