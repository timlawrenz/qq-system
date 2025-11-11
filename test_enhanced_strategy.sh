#!/usr/bin/env bash
# test_enhanced_strategy.sh - Test Enhanced Congressional Trading Strategy
#
# This script runs the enhanced strategy alongside the simple strategy
# for comparison WITHOUT executing any trades.
#
# Usage: ./test_enhanced_strategy.sh

set -e  # Exit on error
set -a  # Export all variables

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "================================================================"
echo " Enhanced Strategy Testing - No Trades Executed"
echo " Started at: $(date)"
echo "================================================================"
echo ""

# Ensure we're in the right directory
cd "$(dirname "$0")"

# Load environment variables
if [ -f .env ]; then
  source .env
fi

# Step 1: Score politicians (if needed)
echo -e "${BLUE}Step 1: Scoring politicians...${NC}"
bundle exec rails runner "
  # Check if we need to score
  needs_scoring = PoliticianProfile.where('last_scored_at IS NULL OR last_scored_at < ?', 1.week.ago).exists?
  
  if needs_scoring || PoliticianProfile.count == 0
    puts '  Running politician scoring job...'
    ScorePoliticiansJob.perform_now
    puts \"${GREEN}✓${NC} Politicians scored\"
  else
    puts \"${GREEN}✓${NC} Politicians already scored recently (#{PoliticianProfile.with_quality_score.count} profiles)\"
  end
"

# Step 2: Generate Simple Strategy Portfolio
echo ""
echo -e "${BLUE}Step 2: Generating SIMPLE strategy portfolio...${NC}"
bundle exec rails runner "
  result = TradingStrategies::GenerateTargetPortfolio.call
  
  if result.failure?
    puts \"${RED}✗ Simple strategy failed: #{result.errors.full_messages.join(', ')}${NC}\"
    exit 1
  end
  
  positions = result.target_positions
  total_value = positions.sum(&:target_value)
  
  puts \"${GREEN}✓${NC} Simple Strategy Results:\"
  puts \"  - Positions: #{positions.size}\"
  puts \"  - Total allocation: \$#{total_value.round(2)}\"
  
  if positions.any?
    puts ''
    puts '  Top 5 positions:'
    positions.sort_by { |p| -p.target_value }.first(5).each do |pos|
      puts \"    - #{pos.symbol}: \$#{pos.target_value.round(2)}\"
    end
  end
  
  # Store for comparison
  File.write('tmp/simple_strategy_positions.json', positions.map { |p| 
    { symbol: p.symbol, target_value: p.target_value.to_f }
  }.to_json)
"

# Step 3: Generate Enhanced Strategy Portfolio
echo ""
echo -e "${BLUE}Step 3: Generating ENHANCED strategy portfolio...${NC}"
bundle exec rails runner "
  # Try with default settings first
  result = TradingStrategies::GenerateEnhancedCongressionalPortfolio.call(
    enable_committee_filter: true,
    min_quality_score: 5.0,
    enable_consensus_boost: true,
    lookback_days: 45
  )
  
  if result.failure?
    error_msg = result.error || 'Unknown error'
    puts \"${RED}✗ Enhanced strategy failed: #{error_msg}${NC}\"
    puts \"${YELLOW}⚠${NC} Trying with relaxed filters...\"
    
    # Retry with committee filter disabled
    result = TradingStrategies::GenerateEnhancedCongressionalPortfolio.call(
      enable_committee_filter: false,
      min_quality_score: 5.0,
      enable_consensus_boost: true,
      lookback_days: 45
    )
  end
  
  if result.failure?
    puts \"${RED}✗ Enhanced strategy failed even with relaxed filters${NC}\"
    exit 1
  end
  
  positions = result.target_positions
  total_value = positions.sum(&:target_value)
  filters = result.filters_applied
  stats = result.stats
  
  puts \"${GREEN}✓${NC} Enhanced Strategy Results:\"
  puts \"  - Positions: #{positions.size}\"
  puts \"  - Total allocation: \$#{total_value.round(2)}\"
  puts \"  - Filters: #{filters.inspect}\"
  puts \"  - Stats: #{stats.inspect}\"
  
  if positions.any?
    puts ''
    puts '  Top 5 positions:'
    positions.sort_by { |p| -p.target_value }.first(5).each do |pos|
      details = pos.details || {}
      puts \"    - #{pos.symbol}: \$#{pos.target_value.round(2)} (#{details[:politician_count]} politicians, Q: #{details[:quality_multiplier]}, C: #{details[:consensus_multiplier]})\"
    end
  end
  
  # Store for comparison
  File.write('tmp/enhanced_strategy_positions.json', positions.map { |p|
    {
      symbol: p.symbol,
      target_value: p.target_value.to_f,
      details: p.details
    }
  }.to_json)
"

# Step 4: Compare Results
echo ""
echo -e "${BLUE}Step 4: Comparing strategies...${NC}"
bundle exec rails runner "
  require 'json'
  
  simple = JSON.parse(File.read('tmp/simple_strategy_positions.json'))
  enhanced = JSON.parse(File.read('tmp/enhanced_strategy_positions.json'))
  
  simple_tickers = simple.map { |p| p['symbol'] }.to_set
  enhanced_tickers = enhanced.map { |p| p['symbol'] }.to_set
  
  common_tickers = simple_tickers & enhanced_tickers
  simple_only = simple_tickers - enhanced_tickers
  enhanced_only = enhanced_tickers - simple_tickers
  
  puts \"${GREEN}✓${NC} Comparison:\"
  puts \"  - Common positions: #{common_tickers.size}\"
  puts \"  - Simple-only positions: #{simple_only.size}\"
  puts \"  - Enhanced-only positions: #{enhanced_only.size}\"
  
  if simple_only.any?
    puts ''
    puts \"  Removed by enhanced filters: #{simple_only.to_a.join(', ')}\"
  end
  
  if enhanced_only.any?
    puts ''
    puts \"  Added by enhanced logic: #{enhanced_only.to_a.join(', ')}\"
  end
  
  # Calculate position size differences for common tickers
  if common_tickers.any?
    puts ''
    puts '  Position size changes for common tickers:'
    common_tickers.first(5).each do |ticker|
      simple_pos = simple.find { |p| p['symbol'] == ticker }
      enhanced_pos = enhanced.find { |p| p['symbol'] == ticker }
      
      simple_val = simple_pos['target_value']
      enhanced_val = enhanced_pos['target_value']
      pct_change = ((enhanced_val - simple_val) / simple_val * 100).round(2)
      
      puts \"    - #{ticker}: \$#{simple_val.round(2)} → \$#{enhanced_val.round(2)} (#{pct_change > 0 ? '+' : ''}#{pct_change}%)\"
    end
  end
  
  # Save comparison report
  report = {
    timestamp: Time.current.iso8601,
    simple_strategy: {
      position_count: simple.size,
      total_value: simple.sum { |p| p['target_value'] }
    },
    enhanced_strategy: {
      position_count: enhanced.size,
      total_value: enhanced.sum { |p| p['target_value'] }
    },
    comparison: {
      common_positions: common_tickers.size,
      simple_only: simple_only.to_a,
      enhanced_only: enhanced_only.to_a
    }
  }
  
  File.write('tmp/strategy_comparison_report.json', JSON.pretty_generate(report))
  puts ''
  puts \"${GREEN}✓${NC} Full report saved to: tmp/strategy_comparison_report.json\"
"

echo ""
echo "================================================================"
echo -e " ${GREEN}Strategy Comparison Complete${NC}"
echo " No trades were executed - this was a test run only"
echo " Finished at: $(date)"
echo "================================================================"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Review the comparison above"
echo "  2. Check tmp/strategy_comparison_report.json for details"
echo "  3. Run this script daily to track performance differences"
echo "  4. After 1-2 weeks, evaluate if enhanced strategy should replace simple"
