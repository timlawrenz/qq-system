# Daily Trading Process Guide

**Last Updated:** 2025-11-08

This guide outlines the manual day-to-day trading process for the QuiverQuant system. These steps can later be automated via cron jobs.

---

## Overview

The trading system follows this workflow:
1. **Fetch congressional trading data** from QuiverQuant API
2. **Generate target portfolio** based on the Simple Momentum Strategy
3. **Execute trades** on Alpaca paper trading to match the target
4. **Monitor and verify** the orders were placed successfully

---

## Prerequisites

### Environment Setup
```bash
# Ensure your .env file has all required credentials:
# - QUIVER_API_TOKEN
# - ALPACA_API_KEY_ID
# - ALPACA_API_SECRET_KEY
# - ALPACA_API_ENDPOINT

# Verify database is running (PostgreSQL on localhost:5432)
# Verify you're in the project root
cd /home/tim/source/activity/qq-system
```

### One-Time Setup (if not done)
```bash
# Install dependencies
bundle install

# Set up databases
bundle exec rails db:setup

# Verify QuiverQuant API access
bundle exec rake debug:quiver_client
```

---

## Daily Process (Manual)

### Step 1: Fetch Latest Congressional Trading Data

**Purpose:** Import new congressional trades from the last 7 days to keep signals fresh.

```bash
# Option A: Fetch last 7 days of data (recommended for daily runs)
bundle exec rails runner "
  client = QuiverClient.new
  trades = client.fetch_congressional_trades(
    start_date: 7.days.ago.to_date,
    end_date: Date.current
  )
  
  new_count = 0
  trades.each do |trade_data|
    qt = QuiverTrade.find_or_create_by!(
      ticker: trade_data[:ticker],
      transaction_date: trade_data[:transaction_date],
      trader_name: trade_data[:trader_name],
      transaction_type: trade_data[:transaction_type]
    ) do |t|
      t.company = trade_data[:company]
      t.trader_source = 'congress'
      t.trade_size_usd = trade_data[:trade_size_usd]
      t.disclosed_at = trade_data[:disclosed_at]
    end
    new_count += 1 if qt.previously_new_record?
  end
  
  puts \"Fetched #{trades.size} trades, #{new_count} new records\"
"

# Option B: Use the rake task (fetches last 2 years - good for initial setup)
bundle exec rake quiver:fetch_historical_signals
```

**Expected Output:**
```
Fetching congressional trades from QuiverQuant API...
Fetched 150 trades, 12 new records
```

**Verification:**
```bash
# Check how many recent congressional purchases we have
bundle exec rails runner "
  count = QuiverTrade.where(transaction_type: 'Purchase')
                     .where('transaction_date >= ?', 45.days.ago)
                     .distinct
                     .count(:ticker)
  puts \"Active signals (purchases in last 45 days): #{count} unique tickers\"
"
```

---

### Step 2: Generate Target Portfolio

**Purpose:** Run the Simple Momentum Strategy to determine what stocks to hold and in what amounts.

```bash
# Generate target portfolio for today
bundle exec rails runner "
  result = TradingStrategies::GenerateTargetPortfolio.call
  
  if result.success?
    positions = result.target_positions
    puts \"Target Portfolio (#{positions.size} positions):\"
    puts '=' * 60
    
    total_value = positions.sum(&:target_value)
    
    positions.sort_by { |p| -p.target_value }.each do |pos|
      pct = (pos.target_value / total_value * 100).round(2)
      puts \"  #{pos.symbol.ljust(6)} - $#{pos.target_value.round(2).to_s.rjust(10)} (#{pct}%)\"
    end
    
    puts '=' * 60
    puts \"Total allocation: $#{total_value.round(2)}\"
  else
    puts \"Failed to generate target portfolio: #{result.errors.full_messages}\"
  end
"
```

**Expected Output:**
```
Target Portfolio (8 positions):
============================================================
  NVDA   - $  12500.00 (12.5%)
  AAPL   - $  12500.00 (12.5%)
  MSFT   - $  12500.00 (12.5%)
  GOOGL  - $  12500.00 (12.5%)
  TSLA   - $  12500.00 (12.5%)
  AMD    - $  12500.00 (12.5%)
  META   - $  12500.00 (12.5%)
  AMZN   - $  12500.00 (12.5%)
============================================================
Total allocation: $100000.00
```

**What's Happening:**
- Strategy looks at all "Purchase" transactions from last 45 days
- Finds unique tickers
- Fetches current account equity from Alpaca
- Divides equity equally among all tickers

---

### Step 3: Execute Trades (Rebalance Portfolio)

**Purpose:** Submit orders to Alpaca to match current holdings with the target portfolio.

```bash
# Execute the rebalancing
bundle exec rails runner "
  # First, generate target
  target_result = TradingStrategies::GenerateTargetPortfolio.call
  
  if target_result.success?
    # Then rebalance to match target
    rebalance_result = Trades::RebalanceToTarget.call(
      target: target_result.target_positions
    )
    
    if rebalance_result.success?
      orders = rebalance_result.orders_placed
      puts \"Successfully placed #{orders.size} orders:\"
      puts '=' * 60
      
      orders.each do |order|
        puts \"  #{order[:side].upcase.ljust(6)} #{order[:symbol].ljust(6)} - Status: #{order[:status]}\"
      end
      
      puts '=' * 60
    else
      puts \"Rebalancing failed: #{rebalance_result.errors.full_messages}\"
    end
  else
    puts \"Failed to generate target: #{target_result.errors.full_messages}\"
  end
"
```

**Alternative: Use the Background Job**
```bash
# Enqueue the job (requires SolidQueue worker running)
bundle exec rails runner "ExecuteSimpleStrategyJob.perform_now"
```

**Expected Output:**
```
Successfully placed 12 orders:
============================================================
  SELL   INTC   - Status: accepted
  SELL   BA     - Status: accepted
  BUY    NVDA   - Status: accepted
  BUY    AAPL   - Status: accepted
  BUY    MSFT   - Status: accepted
  BUY    GOOGL  - Status: accepted
============================================================
```

**What's Happening:**
- Fetches current positions from Alpaca
- Compares current vs target
- Sells positions no longer in target
- Buys/adjusts positions to match target values
- Uses notional (dollar amount) orders for precision
- Creates `AlpacaOrder` records to log every order

---

### Step 4: Verify Orders and Positions

**Purpose:** Confirm orders were executed and portfolio is balanced correctly.

```bash
# Check recent orders in database
bundle exec rails runner "
  orders = AlpacaOrder.where('created_at >= ?', 1.hour.ago).order(created_at: :desc)
  
  puts \"Recent Orders (last hour):\"
  puts '=' * 60
  
  orders.each do |order|
    puts \"  #{order.created_at.strftime('%H:%M')} | #{order.side.upcase.ljust(4)} #{order.symbol.ljust(6)} | #{order.status.ljust(10)} | $#{order.notional || (order.qty.to_f * (order.filled_avg_price || 0)).round(2)}\"
  end
  
  puts '=' * 60
  puts \"Total: #{orders.count} orders\"
"

# Check current Alpaca positions
bundle exec rails runner "
  service = AlpacaService.new
  positions = service.current_positions
  
  puts \"\\nCurrent Alpaca Positions:\"
  puts '=' * 60
  
  total_value = 0
  positions.sort_by { |p| -p[:market_value] }.each do |pos|
    total_value += pos[:market_value]
    puts \"  #{pos[:symbol].ljust(6)} - #{pos[:qty].to_f.to_s.rjust(8)} shares - $#{pos[:market_value].round(2).to_s.rjust(10)}\"
  end
  
  equity = service.account_equity
  cash = equity - total_value
  
  puts '=' * 60
  puts \"Total Positions: $#{total_value.round(2)}\"
  puts \"Cash:            $#{cash.round(2)}\"
  puts \"Total Equity:    $#{equity.round(2)}\"
"
```

**Expected Output:**
```
Recent Orders (last hour):
============================================================
  11:45 | SELL INTC   | filled     | $1250.00
  11:45 | BUY  NVDA   | filled     | $12500.00
  11:45 | BUY  AAPL   | filled     | $12500.00
============================================================
Total: 12 orders

Current Alpaca Positions:
============================================================
  NVDA   -  28.5714 shares - $  12500.00
  AAPL   -  67.5676 shares - $  12500.00
  MSFT   -  29.4118 shares - $  12500.00
  GOOGL  -  71.4286 shares - $  12500.00
============================================================
Total Positions: $100000.00
Cash:            $23.74
Total Equity:    $100023.74
```

---

## Monitoring and Troubleshooting

### Check QuiverQuant Data Freshness
```bash
bundle exec rails runner "
  latest = QuiverTrade.order(transaction_date: :desc).first
  puts \"Most recent congressional trade: #{latest.ticker} on #{latest.transaction_date}\"
  puts \"Disclosed at: #{latest.disclosed_at}\"
"
```

### View Strategy Signal Details
```bash
bundle exec rails runner "
  purchases = QuiverTrade.where(transaction_type: 'Purchase')
                         .where('transaction_date >= ?', 45.days.ago)
                         .order(transaction_date: :desc)
                         .limit(20)
  
  puts \"Recent Congressional Purchases (last 45 days):\"
  purchases.each do |t|
    puts \"  #{t.transaction_date} | #{t.ticker.ljust(6)} | #{t.trader_name} | $#{t.trade_size_usd}\"
  end
"
```

### Check Alpaca Account Status
```bash
bundle exec rails runner "
  service = AlpacaService.new
  equity = service.account_equity
  positions = service.current_positions
  
  puts \"Account Equity: $#{equity}\"
  puts \"Number of Positions: #{positions.size}\"
  puts \"Buying Power Available: Check Alpaca dashboard\"
"
```

---

## Common Issues and Solutions

### Issue: "No congressional trades found"
**Solution:** 
- Verify QuiverQuant API credentials in `.env`
- Check API endpoint is correct: `https://api.quiverquant.com`
- Run `bundle exec rake debug:quiver_client` to diagnose

### Issue: "Failed to place order"
**Solution:**
- Verify Alpaca API credentials in `.env`
- Check if market is open (US stock market: Mon-Fri 9:30am-4pm ET)
- Verify you have sufficient buying power
- Check specific error message in logs

### Issue: "Empty target portfolio"
**Solution:**
- Verify you have QuiverTrade records: `bundle exec rails runner "puts QuiverTrade.count"`
- Check if any purchases in last 45 days: `bundle exec rails runner "puts QuiverTrade.purchases.recent(45).count"`
- May need to run `rake quiver:fetch_historical_signals` first

---

## Full Daily Workflow Script

Here's a complete script for daily execution:

```bash
#!/bin/bash
# daily_trading.sh

echo "=== QuiverQuant Daily Trading Process ==="
echo "Started at: $(date)"
echo ""

# Step 1: Fetch new data
echo "Step 1: Fetching congressional trading data..."
bundle exec rails runner "
  client = QuiverClient.new
  trades = client.fetch_congressional_trades(
    start_date: 7.days.ago.to_date,
    end_date: Date.current
  )
  new_count = 0
  trades.each do |td|
    qt = QuiverTrade.find_or_create_by!(
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
    new_count += 1 if qt.previously_new_record?
  end
  puts \"✓ Fetched #{trades.size} trades (#{new_count} new)\"
"

# Step 2 & 3: Generate target and execute trades
echo ""
echo "Step 2: Generating target portfolio and executing trades..."
bundle exec rails runner "ExecuteSimpleStrategyJob.perform_now"

# Step 4: Verify
echo ""
echo "Step 3: Verifying positions..."
bundle exec rails runner "
  service = AlpacaService.new
  positions = service.current_positions
  equity = service.account_equity
  
  puts \"✓ Current positions: #{positions.size}\"
  puts \"✓ Account equity: \$#{equity.round(2)}\"
"

echo ""
echo "=== Daily Trading Complete ==="
echo "Finished at: $(date)"
```

**To use:**
```bash
chmod +x daily_trading.sh
./daily_trading.sh
```

---

## Future: Automation with Cron

Once you're comfortable with the manual process, you can automate it:

```bash
# Edit crontab
crontab -e

# Run daily at 10:00 AM ET (after market open)
0 10 * * 1-5 cd /home/tim/source/activity/qq-system && ./daily_trading.sh >> logs/daily_trading.log 2>&1
```

**Note:** For production automation, you'll need:
1. Error notifications (email/Slack when jobs fail)
2. Market hours checking (don't trade when market is closed)
3. Dry-run mode for testing
4. Position limit checks
5. Performance monitoring

---

## Summary

**Daily Manual Steps:**
1. Fetch latest QuiverQuant data (7 days)
2. Generate target portfolio from strategy
3. Execute rebalancing trades on Alpaca
4. Verify orders and positions

**Key Files:**
- `lib/tasks/quiver.rake` - Data fetching tasks
- `packs/trading_strategies/app/commands/trading_strategies/generate_target_portfolio.rb` - Strategy logic
- `packs/trades/app/commands/trades/rebalance_to_target.rb` - Trade execution
- `packs/trading_strategies/app/jobs/execute_simple_strategy_job.rb` - Combined workflow

**Next Steps:**
- Test the manual workflow daily for 1-2 weeks
- Monitor performance and adjust strategy parameters
- Add error handling and notifications
- Convert to automated cron jobs
