# Daily Trading Process

> **UPDATED**: As of 2025-12-11, we now run a **Blended Multi-Strategy Portfolio** combining Congressional, Lobbying, and Insider trading signals.

## 🎯 Overview

Fully automated trading system with complete API integrations:

- ✅ **QuiverQuant API**: Congressional, Insider, and Lobbying data
- ✅ **Alpaca API**: Paper ($100k) and Live ($1k) trading accounts
- ✅ **Blended Strategy**: Multi-signal portfolio with risk controls
- ✅ **Account Safety**: Enforced single source of truth for account data

## 🚀 Quick Start - Run Daily Trading

### Paper Trading (Recommended for Testing)
```bash
cd /home/tim/source/activity/qq-system
TRADING_MODE=paper ./daily_trading.sh
```

### Live Trading (Real Money)
```bash
cd /home/tim/source/activity/qq-system
TRADING_MODE=live CONFIRM_LIVE_TRADING=yes ./daily_trading.sh
```

**⚠️ IMPORTANT**: `TRADING_MODE` must be set or the script will fail (no defaults).

This script performs all steps automatically:
1. Fetches congressional and insider trading data
2. Scores politicians for quality
3. **Loads account equity ONCE** (single source of truth)
4. Analyzes current signals
5. Generates blended portfolio & executes trades
6. Verifies positions

### Option 2: Manual Step-by-Step

If you prefer to run each step manually or troubleshoot:

```bash
# Step 1: Fetch data
bundle exec rails runner "
  client = QuiverClient.new
  trades = client.fetch_congressional_trades(limit: 1000)
  trades.select { |t| t[:transaction_date] >= 7.days.ago.to_date }.each do |td|
    QuiverTrade.find_or_create_by!(
      ticker: td[:ticker],
      transaction_date: td[:transaction_date],
      trader_name: td[:trader_name],
      transaction_type: td[:transaction_type]
    ) do |t|
      t.company = td[:company]
      t.trader_source = 'congress'
      t.trade_size_usd = td[:trade_size_usd]
      t.disclosed_at = td[:disclosed_at]
    end
  end
  puts 'Data fetched successfully'
"

# Step 2: Execute strategy
bundle exec rails runner "
  target = TradingStrategies::GenerateTargetPortfolio.call
  result = Trades::RebalanceToTarget.call(target: target.target_positions)
  puts \"Orders placed: #{result.orders_placed.size}\"
"

# Step 3: Check positions
bundle exec rails runner "
  service = AlpacaService.new
  puts \"Equity: \$#{service.account_equity}\"
  puts \"Positions: #{service.current_positions.size}\"
"
```

## 📊 How The Blended Strategy Works

### Three-Strategy Portfolio

The system combines three distinct strategies with configurable weights:

1. **Enhanced Congressional Strategy** (45% live, 40% paper)
   - Tracks congressional purchases from last 45 days
   - Scores politicians based on historical performance
   - Filters by quality score (min 4.0-5.0 depending on mode)
   - Boosts positions with consensus (multiple politicians buying same stock)
   - Weights positions by politician quality and consensus

2. **Lobbying Strategy** (35% live, 40% paper)
   - Analyzes corporate lobbying disclosure data
   - Identifies companies increasing lobbying spend
   - Equal-weighted across qualifying tickers

3. **Insider Trading Strategy** (20% in both modes)
   - Tracks corporate insider purchases from QuiverQuant
   - Filters for executive-level purchases (not just directors)
   - Minimum transaction size: $10,000
   - Weights positions by transaction value
   - Lookback: 30 days

### Complete Position Sizing Math

**Example: Paper Account ($102,083)**

#### Step 1: Strategy Allocation
```
Total Equity:     $102,083
Congressional:    40% × $102,083 = $40,833
Lobbying:         40% × $102,083 = $40,833
Insider:          20% × $102,083 = $20,417
```

#### Step 2: Per-Strategy Position Sizing

**Congressional (6 tickers):**
- Base allocation: $40,833 ÷ 6 = $6,805 per ticker
- Apply quality score weighting:
  - Marjorie Taylor Greene (score 9.97): $6,805 × 1.20 = $8,166
  - David McCormick (score 10.0): $6,805 × 1.20 = $8,166
  - David Taylor (score 6.11): $6,805 × 0.95 = $6,465
- Apply consensus boost (if applicable):
  - If 3+ politicians bought same stock: multiply by 1.15
- Result: 6 positions ranging from $5,000-$9,000

**Lobbying (1 ticker):**
- Single position: $40,833 (before risk controls)
- Result: 1 position = $40,833

**Insider (110 tickers):**
- Total allocated: $20,417
- Weight by transaction value:
  - REGN insider bought $5M: weight = 0.45 → $9,188
  - HPE insider bought $1M: weight = 0.09 → $1,838
  - PRO insider bought $500k: weight = 0.045 → $919
- Result: 110 positions ranging from $100-$9,000

#### Step 3: Risk Controls Applied

**Max Position Percentage:**
- Paper: 15% max = $15,312 per position
- Live: 10% max = $100 per position (with $1k account)
- Any position exceeding this gets capped

**Min Position Value:**
- Paper: $1,000 minimum
- Live: $20 minimum
- Any position below this gets filtered out

**Example: Live Account ($1,006.64)**
```
Total Equity:     $1,006.64
Congressional:    45% × $1,006.64 = $453.00
Lobbying:         35% × $1,006.64 = $352.32
Insider:          20% × $1,006.64 = $201.33

Congressional (6 tickers):
  $453 ÷ 6 = $75.50 base per ticker
  After quality weighting: $65-$90 per position
  After min_position_value ($20): All pass ✓

Lobbying (1 ticker):
  $352.32 initial
  After max_position_pct (10% = $100): Capped to $100
  After min_position_value ($20): Passes ✓

Insider (110 tickers):
  $201.33 allocated
  Top position (REGN): $135 → Capped to $100
  Most positions: $2-$20 → Many filtered by $20 minimum
  Final: ~5-10 positions pass filters
```

#### Step 4: Position Merging

**Merge Strategy: Additive**
- If congressional AND insider both pick AAPL:
  - Congressional AAPL: $80
  - Insider AAPL: $45
  - Final AAPL: $125 (additive merge)
  - Then apply max_position_pct cap if needed

**Alternative: Max Strategy**
- Would take max($80, $45) = $80 only
- More conservative, prevents over-concentration

#### Step 5: Final Portfolio

**Paper Account Result:**
- 15-25 positions after all filters
- Typical allocation: $5,000-$15,000 per position
- Total invested: ~80-95% of equity

**Live Account Result:**
- 5-10 positions after all filters  
- Typical allocation: $50-$100 per position
- Total invested: ~50-70% of equity (due to aggressive filters)

### Real Example (from logs)

**Paper Mode ($102,083):**
```
Congressional: 0 positions (filtered by quality)
Lobbying:      1 position  = $40,833 (capped to $15,312)
Insider:       109 positions → 16 after filters
Final:         2 positions executed (REGN, HPE)
```

**Live Mode ($1,006.64):**
```
Congressional: 6 positions = $453 total ($75 each)
Lobbying:      1 position  = $352 (capped to $100)  
Insider:       110 positions → 0 after $20 minimum filter
Final:         6 positions executed (all congressional)
```

## 🔍 Monitoring & Verification

### Check Current Signals (All Sources)
```bash
bundle exec rails runner "
  puts 'Congressional Purchases (45d):'
  QuiverTrade.where(transaction_type: 'Purchase', trader_source: 'congress')
             .where('transaction_date >= ?', 45.days.ago)
             .group(:ticker).count
             .sort_by { |_, count| -count }.first(10)
             .each { |ticker, count| puts \"  #{ticker}: #{count} purchases\" }

  puts \"\\nInsider Purchases (30d):\"
  QuiverTrade.where(transaction_type: 'Purchase', trader_source: 'insider')
             .where('transaction_date >= ?', 30.days.ago)
             .distinct.count(:ticker)
             .then { |count| puts \"  #{count} unique tickers\" }
"
```

### Check Recent Orders
```bash
bundle exec rails runner "
  AlpacaOrder.where('created_at >= ?', 1.day.ago)
             .order(created_at: :desc)
             .each do |order|
               puts \"#{order.created_at.strftime('%H:%M')} | #{order.side.upcase} #{order.symbol} | #{order.status}\"
             end
"
```

### Check Account Status
```bash
bundle exec rails runner "
  service = AlpacaService.new
  equity = service.account_equity
  positions = service.current_positions
  
  puts \"Total Equity: \$#{equity.round(2)}\"
  puts \"Positions: #{positions.size}\"
  
  positions.each do |pos|
    pct = (pos[:market_value] / equity * 100).round(1)
    puts \"  #{pos[:symbol]}: \$#{pos[:market_value].round(2)} (#{pct}%)\"
  end
"
```

## ⏰ Recommended Schedule

### Daily (During Market Hours)
**Best time:** 10:00 AM ET (30 mins after market open)

```bash
cd /home/tim/source/activity/qq-system

# Paper mode (testing)
TRADING_MODE=paper ./daily_trading.sh >> logs/daily_trading_$(date +%Y%m%d).log 2>&1

# Live mode (real money)
TRADING_MODE=live CONFIRM_LIVE_TRADING=yes ./daily_trading.sh >> logs/daily_trading_$(date +%Y%m%d).log 2>&1
```

### Why 10 AM ET?
- Market opens at 9:30 AM ET
- Gives 30 minutes for opening volatility to settle
- Congressional/insider trades disclosed overnight
- QuiverQuant API typically updated by 9 AM ET

## 🔧 Troubleshooting

### No trades being placed?

**1. Check if strategies are generating positions:**
```bash
TRADING_MODE=paper bundle exec rails runner "
  result = TradingStrategies::GenerateBlendedPortfolio.call(
    trading_mode: 'paper',
    total_equity: 100_000
  )
  
  result.strategy_results.each do |strategy, info|
    puts \"#{strategy}: #{info[:positions].size} positions (#{info[:success] ? 'success' : 'failed'})\"
  end
  
  puts \"\\nFinal positions: #{result.target_positions.size}\"
  puts \"Config: min_position_value = \$#{result.config_used['min_position_value']}\"
"
```

**2. If positions generated but all filtered:**
- Check `min_position_value` in `config/portfolio_strategies.yml`
- For $1k account, use $20 minimum
- For $100k account, use $1000 minimum

**3. If no signals in database:**
```bash
bundle exec rails runner "
  puts 'Congressional: ' + QuiverTrade.where(trader_source: 'congress').count.to_s
  puts 'Insider: ' + QuiverTrade.where(trader_source: 'insider').count.to_s
  puts 'Lobbying: ' + LobbyingTrade.count.to_s
"
```

### Market is closed?
Alpaca paper trading API will accept orders outside market hours, but they won't fill until market opens.

### API errors?
```bash
# Test QuiverQuant
bundle exec rails runner "
  client = QuiverClient.new
  trades = client.fetch_congressional_trades(limit: 1)
  puts trades.any? ? 'QuiverQuant OK' : 'QuiverQuant FAILED'
"

# Test Alpaca
bundle exec rails runner "
  service = AlpacaService.new
  equity = service.account_equity
  puts \"Alpaca OK - Equity: \$#{equity}\"
"
```

## 📈 Next Steps

### Phase 1: Paper Trading (Current)
- Run in paper mode daily: `TRADING_MODE=paper ./daily_trading.sh`
- Monitor performance over 2-4 weeks
- Verify strategies are working as expected
- Track fills and slippage

### Phase 2: Live Trading (Micro Account)
- Start with $1k account: `TRADING_MODE=live CONFIRM_LIVE_TRADING=yes ./daily_trading.sh`
- Verify no account mixing issues
- Monitor real execution quality
- Adjust position sizes as account grows

### Phase 3: Automation
Once confident, automate with cron:

```bash
# Edit crontab
crontab -e

# Paper mode (testing)
0 10 * * 1-5 cd /home/tim/source/activity/qq-system && TRADING_MODE=paper ./daily_trading.sh >> logs/daily_$(date +\%Y\%m\%d).log 2>&1

# Live mode (real money) - only enable after paper testing
# 0 10 * * 1-5 cd /home/tim/source/activity/qq-system && TRADING_MODE=live CONFIRM_LIVE_TRADING=yes ./daily_trading.sh >> logs/daily_$(date +\%Y\%m\%d).log 2>&1
```

### Phase 4: Enhancements
- Add Slack/email notifications
- Implement trailing stops
- Add portfolio rebalancing logic
- Create performance dashboard
- Backtest strategy variations
- Add more data sources (government contracts, 13F filings)

## 📁 Key Files

### Execution
- **`./daily_trading.sh`** - Main execution script
- **`packs/trades/app/commands/trades/rebalance_to_target.rb`** - Trade execution

### Strategy Logic
- **`packs/trading_strategies/app/commands/trading_strategies/generate_blended_portfolio.rb`** - Blends all strategies
- **`packs/trading_strategies/app/services/blended_portfolio_builder.rb`** - Position sizing and risk controls
- **`packs/trading_strategies/app/commands/trading_strategies/generate_enhanced_congressional_portfolio.rb`** - Congressional strategy
- **`packs/trading_strategies/app/commands/trading_strategies/generate_lobbying_portfolio.rb`** - Lobbying strategy
- **`packs/trading_strategies/app/commands/trading_strategies/generate_insider_mimicry_portfolio.rb`** - Insider strategy

### Configuration
- **`config/portfolio_strategies.yml`** - Strategy weights, risk controls, per-environment settings
- **`.env`** - API credentials (never commit!)

### Documentation
- **`docs/ACCOUNT_SAFETY_FIX_COMPLETE.md`** - Account isolation architecture
- **`docs/operations/QUIVER_TRADER_UPGRADE.md`** - API tier details

## 🔐 Security Notes

### Account Isolation
- **CRITICAL**: `TRADING_MODE` must be explicitly set (no defaults)
- Account equity loaded ONCE at start (single source of truth)
- Strategies NEVER fetch account data independently
- Impossible to mix paper ($100k) and live ($1k) accounts

### API Keys
- All credentials in `.env` (gitignored)
- Separate keys for paper and live: `ALPACA_PAPER_*` vs `ALPACA_LIVE_*`
- QuiverQuant API key is read-only
- Live trading requires `CONFIRM_LIVE_TRADING=yes` safety flag

### Data Sources
- QuiverQuant: Congressional, Insider, Lobbying data
- Alpaca: Market data, order execution, position tracking
- All data fetched via authenticated APIs

## 📞 Support

For detailed documentation, see `docs/operations/daily-trading-process.md`

For Rails console exploration:
```bash
bundle exec rails console
# Then try:
# QuiverTrade.count
# AlpacaOrder.last
# Algorithm.all
```
