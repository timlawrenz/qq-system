# OpenSpec Proposal: Blended Portfolio System

**Change ID**: `blended-portfolio-system`  
**Status**: Proposed  
**Created**: 2024-12-10  
**Author**: Development Team  
**Estimated Effort**: 2-3 days  
**Priority**: High

---

## Executive Summary

Create a flexible multi-strategy portfolio construction system that combines multiple alpha signals (congressional trading, lobbying influence, committee membership, etc.) into a single unified portfolio with configurable strategy weights and position limits.

This enables:
- Running multiple trading strategies simultaneously
- Configurable allocation across strategies (e.g., 50% congressional, 30% lobbying, 20% committee-focused)
- Automatic position merging and risk controls
- Easy addition of new strategies without disrupting existing ones

---

## Problem Statement

### Current Architecture Limitations

**Current State**:
- Each trading strategy generates a standalone portfolio
- Only ONE strategy can run at a time (via `daily_trading.sh`)
- No way to combine signals from multiple strategies
- Adding new strategies requires choosing: replace old strategy OR run separate accounts

**Example Problem**:
```ruby
# Today in daily_trading.sh (lines 118-125):
# Must choose ONE strategy:
target_result = TradingStrategies::GenerateEnhancedCongressionalPortfolio.call(...)

# Want to add lobbying strategy?
# Option A: Replace congressional (lose that signal)
# Option B: Run separate account (complexity, capital split)
# Option C: Manual merge (error-prone, not sustainable)
```

**Consequence**: 
- Cannot leverage multiple alpha signals simultaneously
- Harder to test new strategies (must commit fully or not at all)
- Cannot gradually roll out strategies (e.g., allocate 10% to test)

---

## Proposed Solution

### High-Level Architecture

Create a **meta-strategy pattern** where individual strategies remain independent but can be combined through a `BlendedPortfolioBuilder`:

```
┌─────────────────────────────────────────────────────────┐
│           BlendedPortfolioBuilder                       │
│  (Configurable strategy weights + position limits)     │
└─────────────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Congressional│ │   Lobbying   │ │  Committee   │
│   Strategy   │ │   Strategy   │ │   Strategy   │
│   (50%)      │ │   (30%)      │ │   (20%)      │
└──────────────┘ └──────────────┘ └──────────────┘
        │               │               │
        └───────────────┼───────────────┘
                        │
                        ▼
              ┌──────────────────┐
              │ Merged Portfolio │
              │ (with position   │
              │  caps & limits)  │
              └──────────────────┘
                        │
                        ▼
              ┌──────────────────┐
              │  RebalanceToTarget│
              └──────────────────┘
```

### Core Principles

1. **Strategy Independence**: Each strategy remains self-contained with its own logic
2. **Configurable Blending**: Strategy weights adjustable via configuration (no code changes)
3. **Automatic Position Merging**: Overlapping positions combined intelligently
4. **Risk Controls**: Position limits, concentration caps, sector limits
5. **Observability**: Track which strategies contributed to each position

---

## Technical Design

### Component 1: BlendedPortfolioBuilder (New)

**Location**: `packs/trading_strategies/app/services/blended_portfolio_builder.rb`

**Responsibility**: Orchestrate multiple strategies and merge results

**Interface**:
```ruby
builder = BlendedPortfolioBuilder.new(
  total_equity: 100_000,
  strategy_weights: {
    congressional: 0.50,    # 50% to congressional signals
    lobbying: 0.30,         # 30% to lobbying factor
    committee_focused: 0.20 # 20% to committee-specific (future)
  },
  options: {
    max_position_pct: 0.15,        # Max 15% in any single stock
    max_sector_pct: 0.30,          # Max 30% in any sector (future)
    min_position_value: 1000,      # Minimum position size
    enable_shorts: true            # Allow short positions
  }
)

result = builder.build
# => {
#   target_positions: [TargetPosition, ...],
#   metadata: {
#     total_positions: 25,
#     strategy_contributions: { congressional: 12, lobbying: 8, committee: 5 },
#     positions_capped: ['AAPL', 'GOOGL'],
#     gross_exposure: 1.0,
#     net_exposure: 0.0
#   }
# }
```

**Key Methods**:
```ruby
class BlendedPortfolioBuilder
  # Run all strategies with allocated equity
  def build
  
  # Merge positions from multiple strategies
  def merge_positions(all_positions)
  
  # Apply risk controls (position caps, sector limits)
  def apply_risk_controls(positions)
  
  # Calculate portfolio metrics
  def calculate_metrics(positions)
end
```

---

### Component 2: Strategy Registry (New)

**Location**: `packs/trading_strategies/app/services/strategy_registry.rb`

**Responsibility**: Central registry of available strategies

**Interface**:
```ruby
class StrategyRegistry
  STRATEGIES = {
    congressional: {
      command: 'TradingStrategies::GenerateEnhancedCongressionalPortfolio',
      params: [:enable_committee_filter, :min_quality_score, :lookback_days],
      default_weight: 0.50,
      rebalance_frequency: :daily,
      description: 'Congressional trading signals with committee relevance'
    },
    lobbying: {
      command: 'TradingStrategies::GenerateLobbyingPortfolio',
      params: [:quarter, :long_pct, :short_pct],
      default_weight: 0.30,
      rebalance_frequency: :quarterly,
      description: 'Corporate lobbying influence factor (simplified)'
    },
    # Future strategies register here
    committee_focused: {
      command: 'TradingStrategies::GenerateCommitteeFocusedPortfolio',
      params: [:min_committee_relevance],
      default_weight: 0.20,
      rebalance_frequency: :daily,
      description: 'Committee membership relevance weighting'
    }
  }
  
  def self.build_strategy(name, allocated_equity:, params: {})
    # Dynamically call strategy with params
  end
  
  def self.list_available
    # Return list of registered strategies
  end
end
```

---

### Component 3: PositionMerger (New)

**Location**: `packs/trading_strategies/app/services/position_merger.rb`

**Responsibility**: Intelligent merging of overlapping positions

**Interface**:
```ruby
class PositionMerger
  def initialize(options = {})
    @merge_strategy = options[:merge_strategy] || :additive
    @max_position_pct = options[:max_position_pct] || 0.15
  end
  
  # Merge strategies:
  # :additive - Sum target values (consensus = stronger signal)
  # :max - Take maximum value (no double-counting)
  # :average - Average target values (conservative)
  def merge(positions)
    grouped = positions.group_by(&:symbol)
    
    grouped.map do |symbol, symbol_positions|
      merged_value = case @merge_strategy
      when :additive
        symbol_positions.sum(&:target_value)
      when :max
        symbol_positions.map(&:target_value).max
      when :average
        symbol_positions.sum(&:target_value) / symbol_positions.size
      end
      
      # Apply position cap
      capped_value = cap_position(merged_value, @max_position_pct)
      
      TargetPosition.new(
        symbol: symbol,
        asset_type: :stock,
        target_value: capped_value,
        metadata: build_metadata(symbol_positions)
      )
    end
  end
  
  private
  
  def build_metadata(positions)
    {
      sources: positions.map { |p| p.metadata&.dig(:source) }.compact.uniq,
      consensus_count: positions.size,
      original_values: positions.map(&:target_value)
    }
  end
end
```

---

### Component 4: Configuration File (New)

**Location**: `config/portfolio_strategies.yml`

**Responsibility**: Declarative strategy configuration

**Example**:
```yaml
# Portfolio strategy configuration
# Loaded by BlendedPortfolioBuilder

default:
  merge_strategy: additive  # additive | max | average
  max_position_pct: 0.15    # Max 15% in single position
  min_position_value: 1000  # Minimum $1000 per position
  enable_shorts: true
  
  strategies:
    congressional:
      enabled: true
      weight: 0.50  # 50% allocation
      params:
        enable_committee_filter: false
        min_quality_score: 4.0
        enable_consensus_boost: true
        lookback_days: 45
    
    lobbying:
      enabled: true
      weight: 0.30  # 30% allocation
      params:
        quarter: current  # 'current' or 'Q4 2025'
        long_pct: 0.5
        short_pct: 0.5
    
    committee_focused:
      enabled: false  # Not implemented yet
      weight: 0.20
      params:
        min_committee_relevance: 0.7

paper:
  # Inherits from default, can override specific values
  strategies:
    congressional:
      weight: 0.60  # Paper account: More conservative
    lobbying:
      weight: 0.40

live:
  # Inherits from default
  strategies:
    congressional:
      weight: 0.50
    lobbying:
      weight: 0.30
    committee_focused:
      enabled: true
      weight: 0.20
```

---

### Component 5: GenerateBlendedPortfolio Command (New)

**Location**: `packs/trading_strategies/app/commands/trading_strategies/generate_blended_portfolio.rb`

**Responsibility**: GLCommand wrapper around BlendedPortfolioBuilder

**Interface**:
```ruby
module TradingStrategies
  class GenerateBlendedPortfolio < GLCommand::Callable
    allows :total_equity, :config_override, :trading_mode
    returns :target_positions, :metadata, :strategy_results
    
    def call
      # Load configuration
      config = load_config(context.trading_mode || Rails.env)
      config.merge!(context.config_override || {})
      
      # Build blended portfolio
      builder = BlendedPortfolioBuilder.new(
        total_equity: context.total_equity || fetch_account_equity,
        strategy_weights: extract_strategy_weights(config),
        options: extract_options(config)
      )
      
      result = builder.build
      
      # Set context
      context.target_positions = result[:target_positions]
      context.metadata = result[:metadata]
      context.strategy_results = result[:strategy_results]
      
      # Logging
      log_portfolio_summary
      
      context
    end
    
    private
    
    def load_config(environment)
      YAML.load_file(
        Rails.root.join('config/portfolio_strategies.yml')
      )[environment]
    end
  end
end
```

---

## Implementation Plan

### Phase 1: Core Infrastructure (Week 1, Days 1-2)

**Tasks**:
1. Create `BlendedPortfolioBuilder` service (4 hours)
   - Basic structure
   - Strategy execution
   - Position collection
   
2. Create `PositionMerger` service (2 hours)
   - Additive merge strategy
   - Position capping
   - Metadata tracking
   
3. Create `StrategyRegistry` (2 hours)
   - Registry structure
   - Dynamic strategy loading
   - Validation
   
4. Unit tests (4 hours)
   - Test each component in isolation
   - Mock strategy results
   - Edge cases

**Deliverable**: Working BlendedPortfolioBuilder that can combine 2+ strategies

---

### Phase 2: Configuration & Command (Week 1, Days 3-4)

**Tasks**:
1. Create `config/portfolio_strategies.yml` (1 hour)
   - Default configuration
   - Environment-specific overrides
   - Documentation
   
2. Create `GenerateBlendedPortfolio` command (2 hours)
   - GLCommand wrapper
   - Configuration loading
   - Error handling
   
3. Integration tests (4 hours)
   - Test with real congressional strategy
   - Test with real lobbying strategy
   - Test configuration loading
   - Test with mock equity ($100k)
   
4. Update `daily_trading.sh` (2 hours)
   - Replace single strategy with blended
   - Add configuration flags
   - Update logging

**Deliverable**: End-to-end working system with configuration

---

### Phase 3: Advanced Features (Week 2, Days 1-2)

**Tasks**:
1. Add merge strategies (2 hours)
   - `:max` merge strategy
   - `:average` merge strategy
   - Configuration switching
   
2. Add sector limits (3 hours)
   - Sector classification (use Industry model)
   - Sector-level caps
   - Rebalancing within sectors
   
3. Add observability (2 hours)
   - Detailed metadata on each position
   - Strategy contribution tracking
   - Portfolio analytics logging
   
4. Performance testing (2 hours)
   - Test with large portfolios (100+ positions)
   - Optimize position merging
   - Memory profiling

**Deliverable**: Production-ready system with advanced features

---

### Phase 4: Documentation & Rollout (Week 2, Day 3)

**Tasks**:
1. User documentation (2 hours)
   - How to configure strategies
   - How to add new strategies
   - Troubleshooting guide
   
2. Developer documentation (2 hours)
   - Architecture diagrams
   - Adding new strategies guide
   - Testing guidelines
   
3. Gradual rollout plan (1 hour)
   - Start with 10% lobbying, 90% congressional
   - Monitor for 1 week
   - Gradually increase to target allocation
   
4. Monitoring setup (2 hours)
   - Add metrics for strategy performance
   - Alert on position limit violations
   - Track strategy contributions

**Deliverable**: Complete documentation and rollout plan

---

## Testing Strategy

### Unit Tests

```ruby
# spec/services/blended_portfolio_builder_spec.rb
RSpec.describe BlendedPortfolioBuilder do
  describe '#build' do
    it 'combines multiple strategies' do
      builder = described_class.new(
        total_equity: 100_000,
        strategy_weights: {
          congressional: 0.6,
          lobbying: 0.4
        }
      )
      
      result = builder.build
      
      expect(result[:target_positions].size).to be > 0
      expect(result[:metadata][:strategy_contributions]).to include(:congressional, :lobbying)
    end
    
    it 'applies position caps' do
      # Test that no position exceeds max_position_pct
    end
    
    it 'handles strategy failures gracefully' do
      # Test when one strategy fails
    end
  end
end

# spec/services/position_merger_spec.rb
RSpec.describe PositionMerger do
  describe '#merge' do
    context 'with additive strategy' do
      it 'sums overlapping positions' do
        positions = [
          TargetPosition.new(symbol: 'AAPL', target_value: 10_000),
          TargetPosition.new(symbol: 'AAPL', target_value: 8_000)
        ]
        
        merger = described_class.new(merge_strategy: :additive)
        result = merger.merge(positions)
        
        expect(result.first.target_value).to eq(18_000)
        expect(result.first.metadata[:consensus_count]).to eq(2)
      end
    end
    
    context 'with position caps' do
      it 'caps positions at max percentage' do
        # Test capping logic
      end
    end
  end
end
```

### Integration Tests

```ruby
# spec/commands/trading_strategies/generate_blended_portfolio_spec.rb
RSpec.describe TradingStrategies::GenerateBlendedPortfolio do
  describe '#call' do
    it 'generates blended portfolio with real strategies' do
      # Setup: Create lobbying data
      create(:lobbying_expenditure, ticker: 'GOOGL', quarter: 'Q4 2025', amount: 5_000_000)
      create(:lobbying_expenditure, ticker: 'AAPL', quarter: 'Q4 2025', amount: 3_000_000)
      
      # Setup: Create congressional trades
      create(:quiver_trade, ticker: 'AAPL', transaction_type: 'Purchase')
      create(:quiver_trade, ticker: 'NVDA', transaction_type: 'Purchase')
      
      result = described_class.call(total_equity: 100_000)
      
      expect(result.success?).to be true
      expect(result.target_positions).to include_ticker('AAPL')  # In both strategies
      expect(result.target_positions).to include_ticker('GOOGL') # Only lobbying
      expect(result.target_positions).to include_ticker('NVDA')  # Only congressional
      
      # AAPL should have higher allocation (consensus)
      aapl_position = result.target_positions.find { |p| p.symbol == 'AAPL' }
      expect(aapl_position.metadata[:sources]).to include(:congressional, :lobbying)
    end
  end
end
```

### Manual Testing Checklist

```markdown
## Pre-Deployment Testing

### Configuration Testing
- [ ] Load config/portfolio_strategies.yml successfully
- [ ] Override specific strategy weights
- [ ] Disable individual strategies
- [ ] Validate required params for each strategy

### Strategy Execution
- [ ] Congressional strategy runs with allocated equity
- [ ] Lobbying strategy runs with allocated equity
- [ ] Both strategies return valid positions
- [ ] Handle strategy failures gracefully

### Position Merging
- [ ] Additive merge: AAPL in both → combined value
- [ ] Position capping: No position > 15%
- [ ] Metadata tracking: Sources recorded correctly
- [ ] Edge case: All positions from one strategy

### Integration with daily_trading.sh
- [ ] Run full workflow with blended portfolio
- [ ] Orders placed correctly
- [ ] Account rebalanced to target
- [ ] Logging shows strategy contributions

### Performance
- [ ] 100 position portfolio merges in < 100ms
- [ ] Memory usage reasonable (< 50MB increase)
- [ ] No N+1 queries

### Edge Cases
- [ ] No congressional signals (lobbying only)
- [ ] No lobbying data (congressional only)
- [ ] Zero equity available
- [ ] All strategies fail
```

---

## Migration Path

### Step 1: Backward Compatibility

**Ensure existing system continues to work**:

```ruby
# daily_trading.sh can still use single strategy:
target_result = TradingStrategies::GenerateEnhancedCongressionalPortfolio.call

# OR use new blended system:
target_result = TradingStrategies::GenerateBlendedPortfolio.call
```

No breaking changes to existing commands.

---

### Step 2: Gradual Rollout (Paper Account)

**Week 1**: Conservative test allocation
```yaml
# config/portfolio_strategies.yml - paper environment
paper:
  strategies:
    congressional:
      weight: 0.90  # 90% to proven strategy
    lobbying:
      weight: 0.10  # 10% to test new strategy
```

**Week 2**: Increase if performing well
```yaml
paper:
  strategies:
    congressional:
      weight: 0.70
    lobbying:
      weight: 0.30
```

**Week 3**: Target allocation
```yaml
paper:
  strategies:
    congressional:
      weight: 0.50
    lobbying:
      weight: 0.50
```

---

### Step 3: Live Account (After Paper Success)

Only move to live after:
1. ✅ 4+ weeks successful paper trading
2. ✅ Blended portfolio outperforms single strategy
3. ✅ No technical issues observed
4. ✅ Risk metrics within tolerance

```yaml
# config/portfolio_strategies.yml - live environment
live:
  strategies:
    congressional:
      weight: 0.60  # Slightly more conservative in live
    lobbying:
      weight: 0.40
```

---

## Risk Analysis

### Technical Risks

**Risk**: Position limits not enforced correctly
- **Impact**: Over-concentration in single stock
- **Mitigation**: Comprehensive unit tests, daily monitoring
- **Probability**: Low (well-tested logic)

**Risk**: Strategy execution failures cascade
- **Impact**: No trades executed
- **Mitigation**: Graceful degradation (skip failed strategy)
- **Probability**: Medium

**Risk**: Configuration errors
- **Impact**: Wrong strategy weights applied
- **Mitigation**: Configuration validation, dry-run mode
- **Probability**: Low

### Trading Risks

**Risk**: Strategies conflict (one long, one short same stock)
- **Impact**: Net position smaller than intended
- **Mitigation**: Visible in metadata, intentional behavior
- **Probability**: High (expected, not a bug)

**Risk**: Higher turnover (multiple strategies rebalancing)
- **Impact**: Increased transaction costs
- **Mitigation**: Monitor turnover metrics, adjust weights
- **Probability**: Medium

**Risk**: Over-diversification (too many small positions)
- **Impact**: Reduced alpha capture
- **Mitigation**: min_position_value setting
- **Probability**: Low

### Operational Risks

**Risk**: Configuration drift between environments
- **Impact**: Paper behaves differently than live
- **Mitigation**: Config file version control, automated testing
- **Probability**: Low

---

## Success Metrics

### Technical Metrics

- **Build Time**: Portfolio generation < 5 seconds
- **Memory**: < 50MB additional memory usage
- **Test Coverage**: > 90% for new components
- **No Regressions**: Existing strategies still work

### Trading Metrics (After 30 Days)

- **Sharpe Ratio**: Blended > single strategy
- **Max Drawdown**: Blended ≤ single strategy (more diversified)
- **Win Rate**: Blended ≥ single strategy
- **Turnover**: Blended < 2x single strategy

### Operational Metrics

- **Configuration Changes**: < 5 minutes to adjust weights
- **New Strategy Addition**: < 1 day to integrate
- **Monitoring**: Full visibility into strategy contributions
- **Incident Rate**: Zero critical incidents in first 90 days

---

## Future Enhancements

### Phase 2b: Market Cap Normalization

Add true lobbying intensity factor:
```ruby
lobbying_intensity:
  weight: 0.30
  params:
    use_market_cap_normalization: true
    market_cap_source: 'alpaca'  # or 'fmp'
```

### Advanced Merge Strategies

```ruby
# Sector-aware merging
merge_strategy: sector_balanced
sector_limits:
  technology: 0.30
  financials: 0.25
  healthcare: 0.20
  energy: 0.15
  other: 0.10
```

### ML-Based Weight Optimization

```ruby
# Learn optimal strategy weights from historical performance
strategy_weights:
  optimization_method: ml_sharpe
  lookback_days: 180
  reoptimize_frequency: monthly
```

### Risk Parity Allocation

```ruby
# Allocate by risk contribution instead of dollar amount
allocation_method: risk_parity
target_volatility: 0.15  # 15% annualized
```

---

## Questions for Review

1. **Merge Strategy**: Should default be `:additive` (consensus = stronger signal) or `:max` (no double-counting)?

2. **Configuration Format**: YAML file vs database table vs ENV variables?

3. **Strategy Registry**: Hardcoded vs dynamic discovery?

4. **Position Caps**: 15% max per position appropriate? Should vary by strategy?

5. **Rebalancing Frequency**: Should lobbying strategy cache results until next quarter?

6. **Rollout Timeline**: 3-week gradual rollout in paper sufficient before live?

---

## Appendix: Code Examples

### Example 1: Using BlendedPortfolio in daily_trading.sh

```ruby
# Before (single strategy):
target_result = TradingStrategies::GenerateEnhancedCongressionalPortfolio.call

# After (blended):
target_result = TradingStrategies::GenerateBlendedPortfolio.call(
  trading_mode: ENV['TRADING_MODE']  # 'paper' or 'live'
)

# Configuration automatically loaded from config/portfolio_strategies.yml
# No code changes needed to adjust strategy weights
```

### Example 2: Adding a New Strategy

```ruby
# 1. Create strategy command (already follows pattern):
module TradingStrategies
  class GenerateCommitteeFocusedPortfolio < GLCommand::Callable
    allows :total_equity, :min_committee_relevance
    returns :target_positions
    
    def call
      # Strategy logic...
    end
  end
end

# 2. Register in config/portfolio_strategies.yml:
strategies:
  committee_focused:
    enabled: true
    weight: 0.20
    params:
      min_committee_relevance: 0.7

# 3. Done! Blended system automatically picks it up
```

### Example 3: Custom Configuration

```ruby
# Override configuration at runtime:
TradingStrategies::GenerateBlendedPortfolio.call(
  config_override: {
    strategy_weights: {
      congressional: 0.40,
      lobbying: 0.60  # Test higher lobbying allocation
    },
    options: {
      max_position_pct: 0.20  # Allow larger positions
    }
  }
)
```

---

## References

### Internal Documentation
- Current congressional strategy: `packs/trading_strategies/app/commands/trading_strategies/generate_enhanced_congressional_portfolio.rb`
- Current lobbying strategy: `packs/trading_strategies/app/commands/trading_strategies/generate_lobbying_portfolio.rb`
- Daily trading workflow: `daily_trading.sh`
- Lobbying implementation: `docs/data/LOBBYING_IMPLEMENTATION_SUMMARY.md`

### External Resources
- **Portfolio Construction Best Practices**: Grinold & Kahn, "Active Portfolio Management"
- **Multi-Factor Models**: Barra Risk Model Handbook
- **Signal Blending**: "Combining Forecasts" (Timmermann, 2006)

---

## Approval Checklist

- [ ] Technical approach validated
- [ ] Risk analysis reviewed
- [ ] Testing strategy approved
- [ ] Timeline reasonable
- [ ] Success metrics defined
- [ ] Rollout plan approved
- [ ] Questions answered
- [ ] Ready to implement

---

**Status**: Awaiting Review  
**Next Steps**: Review proposal → Approve/Modify → Begin Phase 1 implementation
