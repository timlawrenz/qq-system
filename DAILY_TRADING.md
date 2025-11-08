# Daily Trading Process - Quick Reference

## 🎯 Overview

You now have a complete manual trading workflow with all necessary API integrations configured:

- ✅ **QuiverQuant API**: Fetching congressional trading data
- ✅ **Alpaca Paper Trading API**: Executing trades and fetching positions
- ✅ **Simple Momentum Strategy**: Following congress member purchases

## 🚀 Quick Start - Run Daily Trading

### Option 1: Automated Script (Recommended)
```bash
cd /home/tim/source/activity/qq-system
./daily_trading.sh
```

This script performs all 4 steps automatically:
1. Fetches latest congressional trades
2. Analyzes signals
3. Generates target portfolio & executes trades
4. Verifies positions

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

## 📊 How The Strategy Works

**Simple Momentum Strategy:**
1. Looks at all congressional "Purchase" transactions from last 45 days
2. Identifies unique stock tickers
3. Allocates portfolio equity equally across all tickers
4. Rebalances daily to maintain equal weights

**Example:**
- If 10 congress members bought 8 different stocks in last 45 days
- Portfolio value: $100,000
- Strategy allocates: $12,500 to each of the 8 stocks (equal weight)

## 🔍 Monitoring & Verification

### Check Current Signals
```bash
bundle exec rails runner "
  QuiverTrade.where(transaction_type: 'Purchase')
             .where('transaction_date >= ?', 45.days.ago)
             .group(:ticker)
             .count
             .sort_by { |_, count| -count }
             .first(10)
             .each { |ticker, count| puts \"#{ticker}: #{count} purchases\" }
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
./daily_trading.sh >> logs/daily_trading_$(date +%Y%m%d).log 2>&1
```

### Why 10 AM ET?
- Market opens at 9:30 AM ET
- Gives 30 minutes for opening volatility to settle
- Congressional trades are typically disclosed overnight or early morning

## 🔧 Troubleshooting

### No trades being placed?
```bash
# Check if you have purchase signals
bundle exec rails runner "
  count = QuiverTrade.where(transaction_type: 'Purchase')
                     .where('transaction_date >= ?', 45.days.ago)
                     .distinct
                     .count(:ticker)
  puts \"Active signals: #{count}\"
"
# If 0, you need to fetch more data or wait for new congressional trades
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

### Phase 1: Manual Operation (1-2 weeks)
- Run `./daily_trading.sh` manually each day
- Monitor performance
- Get comfortable with the workflow

### Phase 2: Automation
Once you're confident, automate with cron:

```bash
# Edit crontab
crontab -e

# Add this line (runs weekdays at 10 AM ET)
0 10 * * 1-5 cd /home/tim/source/activity/qq-system && ./daily_trading.sh >> logs/daily_$(date +\%Y\%m\%d).log 2>&1
```

### Phase 3: Enhancements
- Add email/Slack notifications
- Implement position size limits
- Add stop-loss logic
- Create performance dashboard
- Backtest parameter variations

## 📁 Key Files

- **`./daily_trading.sh`** - Main execution script
- **`docs/daily-trading-process.md`** - Detailed documentation
- **`packs/trading_strategies/app/commands/trading_strategies/generate_target_portfolio.rb`** - Strategy logic
- **`packs/trades/app/commands/trades/rebalance_to_target.rb`** - Trade execution
- **`.env`** - API credentials (never commit!)

## 🔐 Security Notes

- All API credentials are in `.env` (gitignored)
- Using Alpaca **paper trading** account (no real money)
- QuiverQuant API key is read-only

## 📞 Support

For detailed documentation, see `docs/daily-trading-process.md`

For Rails console exploration:
```bash
bundle exec rails console
# Then try:
# QuiverTrade.count
# AlpacaOrder.last
# Algorithm.all
```
