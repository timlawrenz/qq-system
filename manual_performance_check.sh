#!/usr/bin/env bash
# manual_performance_check.sh - Simple Performance Metrics
#
# Quick script to check your trading performance manually
# Uses the working calculator directly without the full command

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get trading mode
TRADING_MODE=${TRADING_MODE:-paper}

echo "================================================================"
echo " Performance Check (${TRADING_MODE^^} mode)"
echo " $(date)"
echo "================================================================"
echo ""

cd "$(dirname "$0")"

if [ -f .env ]; then
  source .env
fi

export SECRET_KEY_BASE=$(bundle exec rails secret)

bundle exec rails runner "
  service = AlpacaService.new
  calc = PerformanceCalculator.new
  
  # Get current equity
  current_equity = service.account_equity
  puts '📊 Account Status:'
  puts \"  Current Equity: \$#{current_equity.round(2)}\"
  puts \"\"
  
  # Get 30-day history
  history = service.account_equity_history(start_date: 30.days.ago.to_date)
  
  if history.empty?
    puts \"${YELLOW}⚠${NC}  No historical data available yet (new account)\"
    puts \"  Performance metrics require 30+ days of trading history\"
    exit 0
  end
  
  puts \"  History: #{history.count} data points (#{history.first[:timestamp]} to #{history.last[:timestamp]})\"
  puts \"\"
  
  # Calculate metrics
  equity_values = history.map { |h| h[:equity].to_f }
  start_equity = equity_values.first
  end_equity = equity_values.last
  
  if history.last[:profit_loss]
    # Use Alpaca's P&L which accounts for deposits/withdrawals
    total_pnl = history.last[:profit_loss].to_f
    pnl_pct = (history.last[:profit_loss_pct].to_f * 100).round(2)
    puts \"  (Adjusted for deposits/withdrawals)\"
  else
    # Fallback for old data or paper trading sometimes
    total_pnl = end_equity - start_equity
    pnl_pct = (total_pnl / start_equity * 100).round(2)
  end
  
  sharpe = calc.calculate_sharpe_ratio(equity_values)
  max_dd = calc.calculate_max_drawdown(equity_values)
  volatility = calc.calculate_volatility(equity_values)
  
  puts '📈 Performance Metrics (Last 30 Days):'
  puts \"  Starting Equity: \$#{start_equity.round(2)}\"
  puts \"  Ending Equity: \$#{end_equity.round(2)}\"
  puts \"  P&L: \$#{total_pnl.round(2)} (#{pnl_pct}%)\"
  puts \"\"
  puts \"  Sharpe Ratio: #{sharpe&.round(2) || 'N/A (need 30+ days)'}\"
  puts \"  Max Drawdown: #{max_dd&.round(2)}%\"
  puts \"  Volatility: #{volatility&.round(2)}%\"
  puts \"\"

  # --- SPY Benchmark ---
  spy_bars = service.get_bars('SPY', start_date: 30.days.ago.to_date)
  if spy_bars.any?
    spy_start = spy_bars.first[:close].to_f
    spy_end = spy_bars.last[:close].to_f
    spy_pnl_pct = ((spy_end - spy_start) / spy_start * 100).round(2)
    
    alpha = (pnl_pct - spy_pnl_pct).round(2)
    
    puts \"📈 vs SPY Benchmark (#{spy_bars.first[:timestamp].to_date} to #{spy_bars.last[:timestamp].to_date}):\"
    puts \"  SPY Return: #{spy_pnl_pct}%\"
    puts \"  Your Alpha: #{alpha}%\"
  else
    puts \"📈 vs SPY Benchmark:\"
    puts \"  Data Unavailable\"
  end
  puts \"\"
  
  if sharpe
    if sharpe > 2.0
      puts \"${GREEN}✓${NC} Excellent risk-adjusted returns!\"
    elsif sharpe > 1.0
      puts \"${GREEN}✓${NC} Good risk-adjusted returns\"
    elsif sharpe > 0
      puts \"${YELLOW}○${NC} Positive but modest returns\"
    else
      puts \"${YELLOW}⚠${NC}  Negative risk-adjusted returns\"
    end
  end
"

echo ""
echo "================================================================"
echo " Performance Check Complete"
echo "================================================================"
