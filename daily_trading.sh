#!/usr/bin/env bash
# daily_trading.sh - QuiverQuant Daily Trading Workflow
#
# This script performs the complete daily trading process:
# 1. Fetches latest congressional trading data from QuiverQuant
# 2. Generates target portfolio based on Simple Momentum Strategy
# 3. Executes trades on Alpaca to match the target
# 4. Verifies positions and logs results

set -e  # Exit on error
set -a  # Export all variables

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "================================================================"
echo " QuiverQuant Daily Trading Process"
echo " Started at: $(date)"
echo "================================================================"
echo ""

# Ensure we're in the right directory
cd "$(dirname "$0")"

# Load environment variables
if [ -f .env ]; then
  source .env
fi

# Step 1: Fetch congressional trading data
echo -e "${BLUE}Step 1: Fetching congressional trading data...${NC}"
bundle exec rails runner "
  client = QuiverClient.new
  # Fetch last 7 days to catch any late filings
  trades = client.fetch_congressional_trades(
    start_date: 7.days.ago.to_date,
    end_date: Date.current,
    limit: 1000
  )
  
  # Filter and store only from last 7 days
  new_count = 0
  recent_trades = trades.select { |t| t[:transaction_date] >= 7.days.ago.to_date }
  
  recent_trades.each do |trade_data|
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
  
  puts \"${GREEN}✓${NC} Processed #{recent_trades.size} recent trades, #{new_count} new records\"
"

# Step 2: Check current strategy signals
echo ""
echo -e "${BLUE}Step 2: Analyzing current signals...${NC}"
bundle exec rails runner "
  purchase_count = QuiverTrade.where(transaction_type: 'Purchase')
                              .where('transaction_date >= ?', 45.days.ago)
                              .distinct
                              .count(:ticker)
  
  total_count = QuiverTrade.count
  
  puts \"${GREEN}✓${NC} Total congressional trades in database: #{total_count}\"
  puts \"${GREEN}✓${NC} Active purchase signals (last 45 days): #{purchase_count} unique tickers\"
"

# Step 3: Generate target portfolio and execute trades
echo ""
echo -e \"${BLUE}Step 3: Generating target portfolio and executing trades...${NC}\"
bundle exec rails runner "
  # Generate target
  target_result = TradingStrategies::GenerateTargetPortfolio.call
  
  if target_result.failure?
    puts \"${RED}✗ Failed to generate target portfolio: #{target_result.errors.full_messages.join(', ')}${NC}\"
    exit 1
  end
  
  positions = target_result.target_positions
  puts \"${GREEN}✓${NC} Target portfolio: #{positions.size} positions\"
  
  if positions.empty?
    puts \"${BLUE}ℹ${NC} No positions in target (no purchase signals or no equity)\"
    puts \"${BLUE}ℹ${NC} Skipping trade execution\"
    exit 0
  end
  
  # Execute rebalancing
  rebalance_result = Trades::RebalanceToTarget.call(target: positions)
  
  if rebalance_result.failure?
    puts \"${RED}✗ Rebalancing failed: #{rebalance_result.errors.full_messages.join(', ')}${NC}\"
    exit 1
  end
  
  orders = rebalance_result.orders_placed
  puts \"${GREEN}✓${NC} Placed #{orders.size} orders\"
  
  # Log order details
  if orders.any?
    puts ''
    puts 'Orders placed:'
    orders.each do |order|
      puts \"  - #{order[:side].upcase} #{order[:symbol]} (#{order[:status]})\"
    end
  end
"

# Step 4: Verify final positions
echo ""
echo -e "${BLUE}Step 4: Verifying positions...${NC}"
bundle exec rails runner "
  service = AlpacaService.new
  positions = service.current_positions
  equity = service.account_equity
  
  holdings_value = positions.sum { |p| p[:market_value] }
  cash = equity - holdings_value
  
  puts \"${GREEN}✓${NC} Account equity: \\\$#{equity.round(2)}\"
  puts \"${GREEN}✓${NC} Current positions: #{positions.size}\"
  puts \"${GREEN}✓${NC} Holdings value: \\\$#{holdings_value.round(2)}\"
  puts \"${GREEN}✓${NC} Cash: \\\$#{cash.round(2)}\"
  
  if positions.any?
    puts ''
    puts 'Top positions:'
    positions.sort_by { |p| -p[:market_value] }.first(5).each do |pos|
      pct = (pos[:market_value] / equity * 100).round(2)
      puts \"  - #{pos[:symbol]}: \\\$#{pos[:market_value].round(2)} (#{pct}%)\"
    end
  end
"

echo ""
echo "================================================================"
echo -e " ${GREEN}Daily Trading Complete${NC}"
echo " Finished at: $(date)"
echo "================================================================"
