#!/usr/bin/env bash
# weekly_performance_report.sh - Generate Weekly Performance Report
#
# Generates a comprehensive performance report comparing strategy
# performance to SPY benchmark

set -e  # Exit on error
set -a  # Export all variables

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "================================================================"
echo " QuiverQuant Weekly Performance Report"
echo " Generated at: $(date)"
echo "================================================================"
echo ""

# Ensure we're in the right directory
cd "$(dirname "$0")"

# Load environment variables
if [ -f .env ]; then
  source .env
fi

# Set SECRET_KEY_BASE
export SECRET_KEY_BASE=$(bundle exec rails secret)

# Generate report
echo -e "${BLUE}Generating performance report...${NC}"
bundle exec rails runner "
  result = GeneratePerformanceReport.call(
    strategy_name: 'Enhanced Congressional'
  )
  
  if result.success?
    puts \"${GREEN}✓${NC} Report generated successfully\"
    puts \"  File: #{result.file_path}\"
    puts \"  Database ID: #{result.snapshot_id}\"
    puts \"\"
    
    # Print summary
    report = result.report_hash
    strategy = report[:strategy]
    
    puts '📊 Performance Summary:'
    puts \"  Total Equity: \$#{strategy[:total_equity]&.round(2)}\"
    puts \"  P&L: \$#{strategy[:total_pnl]&.round(2)} (#{strategy[:pnl_pct]&.round(2)}%)\"
    puts \"  Sharpe Ratio: #{strategy[:sharpe_ratio]&.round(2) || 'N/A'}\"
    puts \"  Max Drawdown: #{strategy[:max_drawdown_pct]&.round(2)}%\"
    puts \"  Win Rate: #{strategy[:win_rate]&.round(2)}%\" if strategy[:win_rate]
    puts \"\"
    
    if report[:benchmark]
      benchmark = report[:benchmark]
      puts '📈 vs SPY Benchmark:'
      puts \"  Alpha: #{benchmark[:alpha]&.round(4) || 'N/A'}\"
      puts \"  Beta: #{benchmark[:beta]&.round(4) || 'N/A'}\"
      puts \"\"
    end
    
    if report[:warnings]&.any?
      puts \"${BLUE}ℹ${NC} Warnings:\"
      report[:warnings].each { |w| puts \"  - #{w}\" }
    end
  else
    puts \"${RED}✗${NC} Report generation failed\"
    puts \"  Error: #{result.errors.full_messages.join(', ')}\"
    exit 1
  end
"

echo ""
echo "================================================================"
echo " Weekly Performance Report Complete"
echo " Finished at: $(date)"
echo "================================================================"
