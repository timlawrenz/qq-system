# Quick Start: Enhanced Strategy Testing

## TL;DR

Run this **daily after your normal trading** to compare strategies without affecting live trades:

```bash
./test_enhanced_strategy.sh
```

Then review: `tmp/strategy_comparison_report.json`

---

## First-Time Setup (5 minutes)

```bash
# 1. Seed committee/industry data (one-time)
bundle exec rails congressional_strategy:seed_data

# 2. Run initial test
./test_enhanced_strategy.sh
```

---

## Daily Workflow

### Morning (Business as Usual)
```bash
# Run your normal trading script
./daily_trading.sh
```
☝️ This uses **Simple strategy** and executes real trades (no change)

### After Trading (New - Testing)
```bash
# Run comparison test
./test_enhanced_strategy.sh
```
☝️ This compares Simple vs Enhanced **without executing trades**

### Review Results
```bash
# View comparison report
cat tmp/strategy_comparison_report.json

# Or check the script output logs
tail -100 logs/strategy_comparison.log
```

---

## What You'll See

```
Simple Strategy Results:
  - Positions: 12
  - Top 5: AAPL, MSFT, GOOGL, AMZN, TSLA

Enhanced Strategy Results:
  - Positions: 8
  - Filters: {committee: true, min_quality: 5.0, consensus: true}
  - Top 5: NVDA (3 politicians, Q:8.5), AMD, TSM, GOOGL, META

Comparison:
  - Common: 6 positions
  - Removed by enhanced: AAPL, MSFT (low quality scores)
  - Added by enhanced: NVDA, AMD (high consensus)
```

---

## Decision Point (After 1-2 Weeks)

**If enhanced strategy looks good:**

1. Edit `daily_trading.sh` line 86
2. Change from:
   ```ruby
   target_result = TradingStrategies::GenerateTargetPortfolio.call
   ```
3. To:
   ```ruby
   target_result = TradingStrategies::GenerateEnhancedCongressionalPortfolio.call(
     enable_committee_filter: true,
     min_quality_score: 5.0,
     enable_consensus_boost: true
   )
   ```

**If enhanced needs tuning:**
- Lower `min_quality_score` (try 4.0 or 3.0)
- Disable `enable_committee_filter` if too restrictive
- Adjust `lookback_days` (default 45)

---

## Automation (Optional)

Add to crontab:
```bash
# Daily trading (unchanged)
30 9 * * 1-5 cd /path/to/qq-system && ./daily_trading.sh >> logs/daily_trading.log 2>&1

# Strategy comparison (new)
0 10 * * 1-5 cd /path/to/qq-system && ./test_enhanced_strategy.sh >> logs/strategy_comparison.log 2>&1
```

---

## Troubleshooting

**"Enhanced strategy generated 0 positions"**
```bash
# Make sure politicians are scored
bundle exec rails runner "ScorePoliticiansJob.perform_now"
```

**"No committee data"**
```bash
# Re-seed committees and industries
bundle exec rails congressional_strategy:seed_data
```

---

## Files Reference

| File | Purpose |
|------|---------|
| `daily_trading.sh` | Production trading (Simple strategy) |
| `test_enhanced_strategy.sh` | Comparison testing (no trades) |
| `tmp/strategy_comparison_report.json` | Daily comparison results |
| `docs/testing/testing-enhanced-strategy.md` | Full testing guide |
| `docs/strategy/ENHANCED_STRATEGY_IMPLEMENTATION.md` | Technical documentation |

---

## Support

Questions? Check:
- Full testing guide: `docs/testing/testing-enhanced-strategy.md`
- Implementation details: `docs/strategy/ENHANCED_STRATEGY_IMPLEMENTATION.md`
- Strategy code: `packs/trading_strategies/app/commands/trading_strategies/generate_enhanced_congressional_portfolio.rb`
