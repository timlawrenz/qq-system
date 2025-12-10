#!/usr/bin/env bash
# daily_trading.sh - QuiverQuant Daily Trading Workflow
#
# This script performs the complete daily trading process:
# 1. Fetches latest congressional trading data from QuiverQuant
# 2. Scores politicians based on historical performance
# 3. Generates target portfolio based on Enhanced Congressional Strategy
# 4. Executes trades on Alpaca to match the target
# 5. Verifies positions and logs results

set -e  # Exit on error
set -a  # Export all variables

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get trading mode
TRADING_MODE=${TRADING_MODE:-paper}

# Set confirmation for live trading
if [ "$TRADING_MODE" = "live" ]; then
  export CONFIRM_LIVE_TRADING=yes
fi

echo "================================================================"
echo " QuiverQuant Daily Trading Process"
echo " Mode: ${TRADING_MODE^^}"
if [ "$TRADING_MODE" = "live" ]; then
  echo -e " ${RED}⚠  LIVE TRADING - REAL MONEY ⚠${NC}"
fi
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


# Step 2: Score politicians
echo ""
echo -e "${BLUE}Step 2: Scoring politicians...${NC}"
bundle exec rails runner "
  needs_scoring = PoliticianProfile.where('last_scored_at IS NULL OR last_scored_at < ?', 1.week.ago).exists?
  
  if needs_scoring || PoliticianProfile.count == 0
    puts '  Running politician scoring job...'
    ScorePoliticiansJob.perform_now
    scored_count = PoliticianProfile.with_quality_score.count
    puts \"✓ Scored #{scored_count} politician profiles\"
  else
    scored_count = PoliticianProfile.with_quality_score.count
    puts \"✓ Politicians already scored recently (#{scored_count} profiles)\"
  end
"

# Step 3: Analyze current signals
echo ""
echo -e "${BLUE}Step 3: Analyzing current signals...${NC}"
bundle exec rails runner "
  purchase_count = QuiverTrade.where(transaction_type: 'Purchase')
                              .where('transaction_date >= ?', 45.days.ago)
                              .distinct
                              .count(:ticker)
  
  total_count = QuiverTrade.count
  
  puts \"${GREEN}✓${NC} Total congressional trades in database: #{total_count}\"
  puts \"${GREEN}✓${NC} Active purchase signals (last 45 days): #{purchase_count} unique tickers\"
"

# Step 4: Generate target portfolio and execute trades
echo ""
echo -e "${BLUE}Step 4: Generating target portfolio (Blended Multi-Strategy)...${NC}"
bundle exec rails runner "
  # Generate target using Blended Portfolio (Congressional + Lobbying)
  # Configuration loaded from config/portfolio_strategies.yml based on trading mode
  target_result = TradingStrategies::GenerateBlendedPortfolio.call(
    trading_mode: '${TRADING_MODE}'
  )
  
  if target_result.failure?
    puts \"\\\${RED}✗ Failed to generate blended portfolio: #{target_result.error || 'Unknown error'}\\\${NC}\"
    puts \"\\\${BLUE}ℹ\\\${NC} Falling back to congressional-only strategy...\"
    
    # Fallback to congressional-only strategy
    target_result = TradingStrategies::GenerateEnhancedCongressionalPortfolio.call(
      enable_committee_filter: false,
      min_quality_score: 4.0,
      enable_consensus_boost: true,
      lookback_days: 45
    )
    
    if target_result.failure?
      puts \"\\\${RED}✗ Congressional strategy also failed: #{target_result.errors.full_messages.join(', ')}\\\${NC}\"
      exit 1
    end
    puts \"\\\${GREEN}✓\\\${NC} Using congressional-only strategy instead\"
  end
  
  positions = target_result.target_positions
  metadata = target_result.try(:metadata)
  strategy_results = target_result.try(:strategy_results)
  
  puts \"${GREEN}✓${NC} Target portfolio: #{positions.size} positions\"
  
  # Show blended portfolio metadata
  if metadata
    puts \"  Strategy contributions: #{metadata[:strategy_contributions].inspect}\"
    puts \"  Exposure: Gross #{(metadata[:gross_exposure_pct] * 100).round(1)}%, Net #{(metadata[:net_exposure_pct] * 100).round(1)}%\"
    puts \"  Merge strategy: #{metadata[:merge_strategy]}\"
    
    if metadata[:positions_capped].any?
      puts \"  ⚠ Capped positions: #{metadata[:positions_capped].join(', ')}\"
    end
  end
  
  # Show individual strategy results
  if strategy_results
    puts ''
    puts '  Strategy execution:'
    strategy_results.each do |strategy, result|
      status = result[:success] ? '✓' : '✗'
      weight_pct = (result[:weight] * 100).round(0)
      puts \"    #{status} #{strategy}: #{result[:positions].size} positions (#{weight_pct}% allocation)\"
    end
  end
  
  if positions.empty?
    puts \"\\\${BLUE}ℹ\\\${NC} No positions in target\"
    puts \"\\\${BLUE}ℹ\\\${NC} Skipping trade execution\"
    exit 0
  end
  
  # Show top positions
  if positions.size > 0
    puts ''
    puts '  Top positions:'
    positions.sort_by { |p| -p.target_value.abs }.first(5).each do |pos|
      side = pos.target_value > 0 ? 'LONG' : 'SHORT'
      details = pos.details || {}
      sources = details[:sources] || []
      consensus = details[:consensus_count]
      
      if consensus && consensus > 1
        puts \"    - \#{side} \#{pos.symbol}: \$\#{pos.target_value.abs.round(2)} (\#{consensus} strategies: \#{sources.join(', ')})\"
      elsif sources.any?
        puts \"    - \#{side} \#{pos.symbol}: \$\#{pos.target_value.abs.round(2)} (\#{sources.first})\"
      else
        puts \"    - \#{side} \#{pos.symbol}: \$\#{pos.target_value.abs.round(2)}\"
      end
    end
  end
  
  # Execute rebalancing
  rebalance_result = Trades::RebalanceToTarget.call(target: positions)
  
  if rebalance_result.failure?
    puts \"\\\${RED}✗ Rebalancing failed: #{rebalance_result.errors.full_messages.join(', ')}\\\${NC}\"
    exit 1
  end
  
  orders = rebalance_result.orders_placed
  executed_orders = orders.select { |o| o[:status] != 'skipped' }
  skipped_orders = orders.select { |o| o[:status] == 'skipped' }
  
  skipped_msg = skipped_orders.any? ? \", skipped #{skipped_orders.size}\" : \"\"
  puts \"${GREEN}✓${NC} Executed #{executed_orders.size} orders#{skipped_msg}\"
  
  # Log order details
  if executed_orders.any?
    puts ''
    puts 'Orders executed:'
    executed_orders.each do |order|
      puts \"  - #{order[:side].upcase} #{order[:symbol]} (#{order[:status]})\"
    end
  end
  
  if skipped_orders.any?
    puts ''
    puts \"\\\${YELLOW}Skipped orders (insufficient buying power):\\\${NC}\"
    skipped_orders.each do |order|
      puts \"  - \#{order[:side].upcase} \#{order[:symbol]} (\$\#{order[:attempted_amount]})\"
    end
    puts \"\\\${BLUE}ℹ\\\${NC} Tip: Add cash to account for better rebalancing flexibility\"
  end
"

# Step 5: Verify final positions
echo ""
echo -e "${BLUE}Step 5: Verifying positions...${NC}"
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
