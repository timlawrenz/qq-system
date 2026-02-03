# Enhanced Strategy Testing Guide

## Overview

This guide explains how to run **parallel testing** of the Simple and Enhanced Congressional Trading strategies without affecting live trading.

## Files

- **`test_enhanced_strategy.sh`** - Test script that runs both strategies side-by-side
- **`daily_trading.sh`** - Production script (runs Simple strategy and executes trades)

## Setup (One-Time)

### 1. Ensure Data is Seeded

```bash
# Seed committee and industry data (one-time)
bundle exec rails congressional_strategy:seed_data
```

### 2. Run Initial Test

```bash
./test_enhanced_strategy.sh
```

This will:
- Score all politicians (creates PoliticianProfile records)
- Generate Simple strategy portfolio
- Generate Enhanced strategy portfolio  
- Compare the two and save a report

## Daily Testing Workflow

### Option A: Manual Daily Testing (Recommended for Week 1)

Run the test script **after** your normal trading run:

```bash
# 1. Run normal trading (executes trades with Simple strategy)
./daily_trading.sh

# 2. Run comparison test (no trades executed)
./test_enhanced_strategy.sh
```

**Schedule:** Run daily for 1-2 weeks to gather comparison data.

### Option B: Automated Daily Testing

Add to your crontab to run after daily trading:

```bash
# Run daily trading at 9:30 AM ET
30 9 * * 1-5 cd /home/tim/source/activity/qq-system && ./daily_trading.sh >> logs/daily_trading.log 2>&1

# Run strategy comparison at 10:00 AM ET (30 mins later)
0 10 * * 1-5 cd /home/tim/source/activity/qq-system && ./test_enhanced_strategy.sh >> logs/strategy_comparison.log 2>&1
```

## Understanding the Output

### Strategy Comparison Report

The script creates `tmp/strategy_comparison_report.json` with:

```json
{
  "timestamp": "2025-11-10T19:00:00Z",
  "simple_strategy": {
    "position_count": 12,
    "total_value": 100000.0
  },
  "enhanced_strategy": {
    "position_count": 8,
    "total_value": 100000.0
  },
  "comparison": {
    "common_positions": 6,
    "simple_only": ["AAPL", "MSFT"],
    "enhanced_only": ["NVDA", "AMD"]
  }
}
```

### Key Metrics to Track

1. **Position Count Difference**
   - Enhanced typically has fewer positions (more selective)
   - Target: 5-15 positions vs Simple's 10-20

2. **Symbol Overlap**
   - How many positions are common?
   - Which stocks get filtered out?
   - Which stocks get boosted?

3. **Position Size Changes**
   - Enhanced uses dynamic weighting
   - High-quality + consensus stocks get larger allocations

## Evaluation Criteria (After 1-2 Weeks)

### Qualitative Assessment

- [ ] Does enhanced strategy make logical sense?
- [ ] Are filtered-out stocks truly lower quality?
- [ ] Are boosted positions from high-quality politicians?
- [ ] Is portfolio well-diversified (>5 positions)?

### Quantitative Assessment (After Trading)

Track these metrics over 1-2 weeks:

1. **Portfolio Concentration**
   - Simple: Equal weight
   - Enhanced: Weighted by quality/consensus

2. **Politician Quality**
   - What's the average quality score of politicians in each portfolio?
   - Enhanced should have higher average quality

3. **Committee Alignment**
   - % of positions with committee oversight
   - Enhanced should have higher % (if filter enabled)

## Making the Switch

### When to Switch to Enhanced Strategy

Switch when **ALL** of these are true:

- [ ] Test script runs successfully for 5+ consecutive days
- [ ] Enhanced strategy produces 5-15 positions consistently
- [ ] Position quality appears higher (subjective review)
- [ ] No major errors in logs
- [ ] You're comfortable with the logic

### How to Switch

Edit `daily_trading.sh` line 86:

**Before (Simple):**
```ruby
target_result = TradingStrategies::GenerateTargetPortfolio.call
```

**After (Enhanced):**
```ruby
target_result = TradingStrategies::GenerateEnhancedCongressionalPortfolio.call(
  enable_committee_filter: true,
  min_quality_score: 5.0,
  enable_consensus_boost: true,
  lookback_days: 45
)
```

### Gradual Rollout (Optional)

For extra safety, you could:

1. **Week 1-2**: Test only (current setup)
2. **Week 3**: Switch to enhanced, but lower position sizes by 50%
3. **Week 4**: Monitor closely, increase to 75% if performing well
4. **Week 5+**: Full allocation if all metrics look good

## Troubleshooting

### "Enhanced strategy generated 0 positions"

This means filters are too strict. The test script will automatically retry with relaxed filters, but check:

1. **No politician profiles**: Run `ScorePoliticiansJob.perform_now`
2. **All scores too low**: Lower `min_quality_score` to 3.0 or 4.0
3. **Committee filter too strict**: Set `enable_committee_filter: false`

### "Politicians not scored"

```bash
bundle exec rails runner "ScorePoliticiansJob.perform_now"
```

### "Committee data missing"

```bash
bundle exec rails congressional_strategy:seed_data
```

## Daily Review Checklist

After each test run:

- [ ] Check `tmp/strategy_comparison_report.json`
- [ ] Note any unusual position changes
- [ ] Review politician quality scores for top positions
- [ ] Check for warnings in output
- [ ] Track cumulative differences over time

## Example Daily Log Entry

```
Date: 2025-11-10
Simple: 12 positions, $100K total
Enhanced: 8 positions, $100K total
Common: 6 positions
Removed: AAPL (no committee), MSFT (low quality score 4.2)
Added: NVDA (consensus 3 politicians, avg quality 8.5)
Notes: Enhanced more concentrated but higher quality
```

## Questions?

Review the full implementation details in:
- `docs/strategy/ENHANCED_STRATEGY_IMPLEMENTATION.md`

Or check the source code:
- `packs/trading_strategies/app/commands/trading_strategies/generate_enhanced_congressional_portfolio.rb`
