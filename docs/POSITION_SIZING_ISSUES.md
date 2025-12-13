# Portfolio Generation Issues - December 12, 2025

## Problem Summary

The paper trading execution revealed multiple issues with position sizing and reporting in the multi-strategy blended portfolio system.

### Actual Output vs Expected
```
Step 5: Generating target portfolio (Blended Multi-Strategy)...
Target portfolio: 3 positions              ← FINAL count
  Strategy contributions: {insider: 3}      ← POST-MERGE count
  Exposure: Gross 15.7%, Net 15.7%

  Strategy execution:
    SUCCESS insider: 95 positions (20% allocation)  ← PRE-MERGE count (WRONG!)
```

### Issues Identified

#### 1. **Insider Strategy Over-Diversification**
- **Generated**: 95 positions from 435 insider purchase signals
- **Allocated**: $20,348 (20% of $101,817 equity)
- **Per Position**: $20,348 / 95 = **$214 average**
- **Problem**: 92 positions below $500 minimum → **silently filtered out**

**Root Cause**:
```ruby
# generate_insider_mimicry_portfolio.rb:129
def create_target_positions(weighted_tickers, equity)
  # NO LIMIT - creates position for EVERY ticker
  weighted_tickers.map do |ticker, weight|
    allocation_pct = (weight / total_weight) * 100
    target_value = equity * (allocation_pct / 100.0)  # Way too small!
    # ...
  end
end
```

#### 2. **Misleading Shell Script Output**
```bash
# daily_trading.sh:236-240
strategy_results.each do |strategy, result|
  status = result[:success] ? 'SUCCESS' : 'FAILED'
  weight_pct = (result[:weight] * 100).round(0)
  puts "    #{status} #{strategy}: #{result[:positions].size} positions (#{weight_pct}% allocation)"
  # BUG: Shows PRE-MERGE count (95), not final count (3)
end
```

**Should Show**:
```
SUCCESS insider: 3 positions (95 generated, 92 filtered) (20% allocation)
```

#### 3. **No Maximum Position Limit**
- Config file has NO `max_positions` setting
- Strategies can generate unlimited positions
- Insider strategy generated 95 positions from 435 signals
- **Need**: Top N positions by weight/value

#### 4. **Silent Position Filtering**
- PositionMerger filters positions below `min_position_value` at line 61
- **No logging** of how many were filtered
- 92 out of 95 positions silently dropped!

### Expected Behavior

#### Insider Strategy Should:
1. **Limit to top N positions** (e.g., top 20 by transaction value)
2. **Calculate proper allocation**: $20,348 / 20 = **$1,017 per position** ✅
3. **Log filtering**: "Generated 95 positions, using top 20"

#### Shell Script Should:
1. Show both pre-merge and post-merge counts
2. Show filtering statistics
3. Example output:
```
Strategy execution:
  SUCCESS insider: 20 positions generated, 3 in final portfolio (20% allocation)
    - 17 positions merged/filtered by consensus and risk controls
```

#### PositionMerger Should:
1. Log filtered positions count
2. Warn if >50% positions filtered

### Financial Impact

**Current State**:
- Allocated: $20,348 (20% of equity)
- Used: $15,461 in 3 positions (76% utilization)
- **Wasted**: $4,887 idle (24% of allocation)

**After Fix** (top 20 positions):
- Allocated: $20,348
- Used: ~$20,000+ across 20 positions (98%+ utilization)
- Better diversification

### Files Requiring Changes

1. `generate_insider_mimicry_portfolio.rb` - Add max_positions limit
2. `portfolio_strategies.yml` - Add max_positions config
3. `position_merger.rb` - Add logging for filtered positions
4. `daily_trading.sh` - Show pre/post-merge counts
5. `blended_portfolio_builder.rb` - Track filtering stats

### Recommended Fixes

#### Priority 1: Add max_positions to Insider Strategy
```yaml
# config/portfolio_strategies.yml
insider:
  enabled: true
  weight: 0.20
  params:
    lookback_days: 30
    min_transaction_value: 10000
    executive_only: true
    position_size_weight_by_value: true
    max_positions: 20  # NEW: Limit to top 20 by weight
```

```ruby
# generate_insider_mimicry_portfolio.rb
def create_target_positions(weighted_tickers, equity)
  return [] if weighted_tickers.empty?
  
  # NEW: Limit to top N positions
  max_positions = context.max_positions || 20
  top_tickers = weighted_tickers.sort_by { |_, weight| -weight }.first(max_positions)
  
  Rails.logger.info(
    "InsiderStrategy: Using top #{top_tickers.size} of #{weighted_tickers.size} tickers"
  )
  
  # Calculate allocations for top positions only
  total_weight = top_tickers.sum { |_, weight| weight }
  # ...
end
```

#### Priority 2: Improve Logging in PositionMerger
```ruby
# position_merger.rb:60-62
def merge(positions)
  return [] if positions.empty?
  
  grouped = positions.group_by(&:symbol)
  merged_positions = grouped.map { |symbol, symbol_positions| merge_symbol_positions(symbol, symbol_positions) }
  
  # NEW: Log filtering
  before_count = merged_positions.size
  filtered_positions = merged_positions.select { |p| p.target_value.abs >= @min_position_value }
  after_count = filtered_positions.size
  filtered_count = before_count - after_count
  
  if filtered_count > 0
    Rails.logger.warn(
      "PositionMerger: Filtered #{filtered_count} of #{before_count} positions " \
      "below minimum value $#{@min_position_value}"
    )
  end
  
  filtered_positions
end
```

#### Priority 3: Better Shell Script Output
```ruby
# daily_trading.sh:234-240
if strategy_results
  puts ''
  puts '  Strategy execution:'
  strategy_results.each do |strategy, result|
    status = result[:success] ? 'SUCCESS' : 'FAILED'
    weight_pct = (result[:weight] * 100).round(0)
    pre_merge_count = result[:positions].size
    
    # Count how many made it to final portfolio
    post_merge_count = positions.count { |p| 
      p.details&.dig(:sources)&.include?(strategy.to_s) || 
      p.details&.dig(:source) == strategy.to_s 
    }
    
    puts "    #{status} #{strategy}: #{post_merge_count} positions in portfolio " \
         "(#{pre_merge_count} generated) (#{weight_pct}% allocation)"
  end
end
```

### Next Steps

1. ✅ Document issues (this file)
2. ⏸️ Add max_positions parameter to insider strategy
3. ⏸️ Update config with max_positions defaults
4. ⏸️ Improve PositionMerger logging
5. ⏸️ Fix shell script reporting
6. ⏸️ Add system specs for position filtering
7. ⏸️ Test with production data

### Test Cases Needed

1. **Insider strategy with 435 signals**
   - Should generate 20 positions (not 95)
   - Each position ≥ $500 minimum
   - ~$1,000 average position size

2. **PositionMerger filtering**
   - Should log filtered positions
   - Should warn if >50% filtered

3. **Shell script output**
   - Should show both pre/post-merge counts
   - Should match actual positions created
