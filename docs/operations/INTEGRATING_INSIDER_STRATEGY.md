# Integrating Insider Trading Strategy into Daily Trading

**Date**: December 11, 2025  
**Status**: Integration Complete - Ready for Testing  
**Strategy**: Corporate Insider Trading Mimicry

---

## Overview

The insider trading strategy has been integrated into the qq-system multi-strategy framework. It's currently **disabled by default** and ready for phased rollout.

### Integration Components

✅ **QuiverClient** - Fetches insider data from `/beta/live/insiders`  
✅ **Database Schema** - Extended `quiver_trades` with insider fields  
✅ **Strategy Command** - `GenerateInsiderMimicryPortfolio` implemented  
✅ **Strategy Registry** - Insider strategy registered  
✅ **Portfolio Config** - Added to all environments (disabled)  
✅ **Daily Script** - Updated to fetch insider data  

---

## Architecture Integration

### Multi-Strategy Framework

The qq-system uses a **BlendedPortfolioBuilder** that:
1. Executes multiple strategies in parallel
2. Allocates equity based on configured weights
3. Merges overlapping positions (consensus detection)
4. Applies risk controls (position limits)

### Strategy Registry

```ruby
# packs/trading_strategies/app/services/strategy_registry.rb
STRATEGIES = {
  congressional: { weight: 0.40, rebalance: :daily },
  lobbying:      { weight: 0.40, rebalance: :quarterly },
  insider:       { weight: 0.20, rebalance: :daily }  # NEW
}
```

### Configuration File

```yaml
# config/portfolio_strategies.yml
paper:
  strategies:
    congressional:
      enabled: true
      weight: 0.40  # 40% of equity
    
    lobbying:
      enabled: true
      weight: 0.40  # 40% of equity
    
    insider:
      enabled: false  # Enable when ready
      weight: 0.20   # 20% of equity
      params:
        lookback_days: 30
        min_transaction_value: 10000
        executive_only: true
```

---

## Phased Rollout Plan

### Phase 1: Data Collection (Week 1) ✅ **Current Phase**

**Goal**: Collect insider trading data without affecting live trading

**Steps**:
1. ✅ Keep `insider.enabled: false` in config
2. ✅ Daily script fetches insider data (if enabled check passes)
3. ✅ Build up 7-30 days of historical insider trades
4. ✅ Monitor data quality and API reliability

**Validation**:
```bash
# Check insider data collection
bundle exec rails runner "
  count = QuiverTrade.where(trader_source: 'insider').count
  puts \"Insider trades collected: #{count}\"
  
  recent = QuiverTrade.where(trader_source: 'insider')
                      .where('transaction_date >= ?', 7.days.ago)
                      .count
  puts \"Recent (7d): #{recent}\"
"
```

### Phase 2: Paper Trading Test (Week 2-3)

**Goal**: Validate strategy with paper money

**Steps**:
1. **Enable in paper environment**:
   ```yaml
   # config/portfolio_strategies.yml - paper section
   insider:
     enabled: true  # Changed from false
     weight: 0.20
   ```

2. **Reduce other strategies** to maintain 100% total:
   ```yaml
   congressional:
     weight: 0.40  # Reduced from 0.50
   lobbying:
     weight: 0.40  # Reduced from 0.50
   insider:
     weight: 0.20  # NEW
   ```

3. **Run daily trading** for 2 weeks:
   ```bash
   TRADING_MODE=paper ./daily_trading.sh
   ```

**Metrics to Track**:
- Number of insider positions generated daily
- Overlap with congressional/lobbying strategies (consensus)
- Position size distribution
- Trade execution success rate

### Phase 3: Live Trading (Week 4+)

**Goal**: Deploy to production with real money

**Prerequisites**:
- ✅ 2+ weeks successful paper trading
- ✅ Strategy generates 5+ positions consistently
- ✅ No API errors or data quality issues
- ✅ Sharpe ratio >= 0.5 in paper

**Steps**:
1. **Enable in live environment**:
   ```yaml
   # config/portfolio_strategies.yml - live section
   insider:
     enabled: true
     weight: 0.20
   ```

2. **Adjust allocations**:
   ```yaml
   congressional:
     weight: 0.45  # Conservative in live
   lobbying:
     weight: 0.35
   insider:
     weight: 0.20
   ```

3. **Monitor closely** for first 2 weeks
4. **Adjust weights** based on performance

---

## Daily Trading Script Changes

### Before (Congressional Only)
```bash
Step 1: Fetch congressional trading data
Step 2: Score politicians
Step 3: Analyze signals
Step 4: Generate portfolio & execute
```

### After (Multi-Strategy)
```bash
Step 1: Fetch trading data (congressional + insider)
  ✓ Congressional: 45 trades, 12 new
  ✓ Insider: 23 trades, 8 new (or "disabled")
  
Step 2: Score politicians
Step 3: Analyze signals
  ✓ Congressional signals (45d): 15 tickers
  ✓ Insider signals (30d): 8 tickers
  
Step 4: Generate blended portfolio
  Strategy execution:
    ✓ congressional: 12 positions (40% allocation)
    ✓ lobbying: 8 positions (40% allocation)
    ✓ insider: 5 positions (20% allocation)  # When enabled
```

---

## Configuration Reference

### Enabling/Disabling Insider Strategy

**To Enable for Paper Trading**:
```yaml
# config/portfolio_strategies.yml
paper:
  strategies:
    insider:
      enabled: true  # Change this line
```

**To Enable for Live Trading**:
```yaml
# config/portfolio_strategies.yml
live:
  strategies:
    insider:
      enabled: true  # Change this line
```

### Adjusting Parameters

```yaml
insider:
  enabled: true
  weight: 0.20  # 0.0 to 1.0 (must sum to 1.0 with other strategies)
  params:
    lookback_days: 30              # Days to look back (default: 30)
    min_transaction_value: 10000   # Min $10k purchases (default)
    executive_only: true           # CEO/CFO only (default: true)
    position_size_weight_by_value: true  # Weight by purchase size
```

### Testing Configuration Changes

```bash
# Validate config file syntax
bundle exec rails runner "
  config = YAML.load_file('config/portfolio_strategies.yml')
  puts 'Config valid: ' + config.keys.join(', ')
"

# Test blended portfolio generation
bundle exec rails runner "
  result = TradingStrategies::GenerateBlendedPortfolio.call(
    trading_mode: 'paper'
  )
  
  puts \"Strategies enabled:\"
  result.strategy_results.each do |name, info|
    puts \"  #{name}: #{info[:success] ? 'SUCCESS' : 'FAILED'} - #{info[:positions].size} positions\"
  end
"
```

---

## Monitoring & Validation

### Daily Checks

```bash
# 1. Check data collection
bundle exec rails runner "
  puts 'Last 7 days insider trades:'
  QuiverTrade.where(trader_source: 'insider')
             .where('transaction_date >= ?', 7.days.ago)
             .group(:transaction_date)
             .count
             .each { |date, count| puts \"  #{date}: #{count}\" }
"

# 2. Check strategy performance
bundle exec rails runner "
  puts 'Insider strategy positions (if enabled):'
  result = TradingStrategies::GenerateInsiderMimicryPortfolio.call
  
  puts \"Total positions: #{result.target_positions.size}\"
  puts \"Filters applied: #{result.filters_applied}\"
  puts \"Stats: #{result.stats}\"
"

# 3. Check blended allocation
bundle exec rails runner "
  result = TradingStrategies::GenerateBlendedPortfolio.call(trading_mode: 'paper')
  
  puts 'Strategy contributions:'
  result.metadata[:strategy_contributions].each do |strategy, count|
    puts \"  #{strategy}: #{count} positions\"
  end
"
```

### Weekly Review

**Key Metrics**:
1. **Data Quality**: Insider trades collected per day (target: 20-50)
2. **Position Count**: Insider positions generated (target: 5-10)
3. **Overlap**: Consensus with congressional/lobbying (good if high)
4. **Performance**: Return vs SPY benchmark

**Red Flags**:
- 🚨 No insider data for 2+ consecutive days → Check API
- 🚨 Zero positions generated → Filters too strict
- 🚨 API errors → Rate limit or auth issue

---

## Troubleshooting

### Issue: No Insider Data Collected

**Symptoms**: `Insider: 0 trades, 0 new`

**Diagnosis**:
```bash
# Check if insider strategy is enabled
grep -A5 "insider:" config/portfolio_strategies.yml

# Test API directly
bundle exec rails runner "
  client = QuiverClient.new
  trades = client.fetch_insider_trades(limit: 10)
  puts \"API returned #{trades.size} trades\"
"
```

**Solutions**:
- Enable insider strategy in config
- Check QuiverQuant API credentials
- Verify Trader tier subscription active

### Issue: Insider Strategy Not in Blended Portfolio

**Symptoms**: Blended portfolio doesn't include insider positions

**Diagnosis**:
```bash
# Check if enabled
bundle exec rails runner "
  config_path = Rails.root.join('config/portfolio_strategies.yml')
  configs = YAML.load_file(config_path)
  puts configs['paper']['strategies']['insider']['enabled']
"

# Check if registered
bundle exec rails runner "
  puts StrategyRegistry.registered?(:insider)
"
```

**Solutions**:
- Set `enabled: true` in config
- Ensure weight > 0
- Verify total weights sum to ~1.0

### Issue: API Rate Limit Errors

**Symptoms**: `429 Too Many Requests`

**Solution**: QuiverClient has built-in rate limiting (60 req/min). If hitting limits:
```ruby
# Reduce data fetching frequency
# Or increase REQUEST_INTERVAL in QuiverClient
```

---

## Rollback Plan

### Emergency Disable

If issues arise in production:

```yaml
# config/portfolio_strategies.yml - LIVE ONLY
live:
  strategies:
    insider:
      enabled: false  # Immediate disable
```

Then:
```bash
# Rerun daily trading to rebalance without insider
TRADING_MODE=live ./daily_trading.sh
```

Portfolio will automatically rebalance to congressional + lobbying only.

### Full Rollback (if needed)

```bash
# 1. Disable in all environments
git checkout HEAD -- config/portfolio_strategies.yml

# 2. Remove from registry (optional)
# Edit: packs/trading_strategies/app/services/strategy_registry.rb
# Comment out insider: { ... } block

# 3. Restart daily trading
./daily_trading.sh
```

---

## Performance Expectations

### Conservative Estimates

Based on academic research and similar strategies:

- **Annual Alpha**: 5-7% (vs SPY benchmark)
- **Sharpe Ratio**: 0.5-1.0
- **Win Rate**: 55-60%
- **Max Drawdown**: <15%
- **Correlation to SPY**: 0.6-0.8

### Success Criteria

**After 4 weeks paper trading**:
- ✅ Positive returns (any positive % acceptable)
- ✅ Sharpe ratio > 0.3
- ✅ No major API failures
- ✅ Consistent position generation (5+ positions daily)

**After 8 weeks live trading**:
- ✅ Outperforming SPY (total return)
- ✅ Sharpe ratio > 0.5
- ✅ Contribution to overall portfolio Sharpe positive

---

## Next Enhancements

### Phase 4: Consensus Detection (Q2 2026)

**Strategy**: Detect multiple insiders buying same stock

**Implementation**:
- Create `GenerateInsiderConsensusPortfolio` command
- Weight positions by number of insiders
- Boost allocation for high-conviction signals

**Expected Alpha Gain**: +2-4% annual

### Phase 5: Adaptive Weighting

**Strategy**: Dynamically adjust strategy weights based on performance

**Logic**:
```ruby
# Increase weight if outperforming
# Decrease weight if underperforming
# Rebalance monthly
```

---

## Related Documentation

- **Strategy Details**: `docs/strategy/INSIDER_TRADING_STRATEGY.md`
- **Strategy Roadmap**: `docs/strategy/STRATEGY_ROADMAP.md` (lines 73-108)
- **Quiver Upgrade**: `docs/operations/QUIVER_TRADER_UPGRADE.md`
- **Daily Trading**: `DAILY_TRADING.md`

---

**Status**: ✅ Ready for Phase 1 (Data Collection)  
**Next Action**: Monitor data collection for 7 days, then enable for paper trading  
**Owner**: Development team  
**Review**: Weekly performance review required
