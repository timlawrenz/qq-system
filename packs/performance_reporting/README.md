# Performance Reporting Pack

Automated performance tracking and analysis for QuiverQuant trading strategies.

## Overview

This pack provides comprehensive performance metrics, benchmarking against SPY, and automated weekly reporting for trading strategies.

## Features

- **Performance Metrics**: Sharpe ratio, max drawdown, volatility, Calmar ratio, win rate
- **Benchmark Comparison**: Alpha and beta calculations vs SPY
- **Automated Reports**: Weekly JSON reports with full performance data
- **Historical Tracking**: Database storage of performance snapshots
- **Flexible Timeframes**: Daily and weekly snapshot support

## Components

### Models

- **PerformanceSnapshot**: Stores performance metrics for a specific date and strategy
  - Indexed by date, strategy, and snapshot type
  - JSON metadata for extensibility

### Services

- **PerformanceCalculator**: Calculates all performance metrics
  - Sharpe ratio (risk-adjusted returns)
  - Maximum drawdown (worst peak-to-trough decline)
  - Volatility (standard deviation of returns)
  - Calmar ratio (return/max drawdown)
  - Win rate (percentage of profitable trades)
  - Annualized returns

- **BenchmarkComparator**: Compares strategy to SPY benchmark
  - Alpha (excess return above benchmark)
  - Beta (correlation to market movements)
  - Automatic SPY data fetching and caching

### Commands

- **GeneratePerformanceReport**: Orchestrates report generation
  - Fetches equity history from Alpaca
  - Calculates all metrics
  - Creates database snapshot
  - Saves JSON report file
  - Handles rollback on failure

### Jobs

- **GeneratePerformanceReportJob**: Background job for scheduled reports
  - Retry logic with exponential backoff
  - Error logging via Sentry

## Usage

### Manual Report Generation

```ruby
# Generate a report for the last 30 days
result = GeneratePerformanceReport.call(
  strategy_name: 'Enhanced Congressional'
)

if result.success?
  puts "Report saved to: #{result.file_path}"
  puts "Snapshot ID: #{result.snapshot_id}"
  puts JSON.pretty_generate(result.report_hash)
end
```

### Custom Date Range

```ruby
result = GeneratePerformanceReport.call(
  start_date: 60.days.ago.to_date,
  end_date: Date.current,
  strategy_name: 'My Strategy'
)
```

### Scheduled Reports

Use the provided script for cron:

```bash
# Weekly report (Sundays at 11 PM)
0 23 * * 0 cd /path/to/qq-system && ./weekly_performance_report.sh >> log/weekly_$(date +\%Y\%m\%d).log 2>&1
```

## Report Structure

Reports are saved as JSON in `tmp/performance_reports/`:

```json
{
  "report_date": "2025-12-09",
  "period": {
    "start_date": "2025-11-09",
    "end_date": "2025-12-09",
    "days": 30
  },
  "strategy": {
    "name": "Enhanced Congressional",
    "total_equity": 103000.00,
    "total_pnl": 3000.00,
    "pnl_pct": 3.0,
    "sharpe_ratio": 0.85,
    "max_drawdown_pct": -2.5,
    "volatility": 12.5,
    "calmar_ratio": 1.2,
    "win_rate": 67.5,
    "total_trades": 24,
    "winning_trades": 16,
    "losing_trades": 8
  },
  "benchmark": {
    "symbol": "SPY",
    "alpha": 0.0023,
    "beta": 0.8,
    "correlation": 0.75
  },
  "warnings": [
    "Limited data: Only 30 days available"
  ]
}
```

## Database Schema

```ruby
create_table :performance_snapshots do |t|
  t.date :snapshot_date, null: false
  t.string :snapshot_type, null: false  # 'daily' or 'weekly'
  t.string :strategy_name, null: false
  
  # Core metrics
  t.decimal :total_equity, precision: 15, scale: 2
  t.decimal :total_pnl, precision: 15, scale: 2
  t.decimal :sharpe_ratio, precision: 8, scale: 4
  t.decimal :max_drawdown_pct, precision: 8, scale: 4
  t.decimal :volatility, precision: 8, scale: 4
  t.decimal :win_rate, precision: 5, scale: 2
  t.integer :total_trades
  t.integer :winning_trades
  t.integer :losing_trades
  t.decimal :calmar_ratio, precision: 8, scale: 4
  
  # Extensibility
  t.jsonb :metadata, default: {}
  
  t.timestamps
end
```

## Querying Performance Data

```ruby
# Get latest weekly snapshot
snapshot = PerformanceSnapshot.weekly
  .by_strategy('Enhanced Congressional')
  .order(snapshot_date: :desc)
  .first

# Get performance over time
snapshots = PerformanceSnapshot.weekly
  .by_strategy('Enhanced Congressional')
  .between_dates(90.days.ago.to_date, Date.current)
  .order(:snapshot_date)

# Calculate metrics
snapshots.each do |s|
  puts "#{s.snapshot_date}: Equity $#{s.total_equity}, Sharpe #{s.sharpe_ratio}"
end
```

## Metrics Interpretation

### Sharpe Ratio
- **> 1.0**: Good risk-adjusted returns
- **> 2.0**: Very good
- **> 3.0**: Excellent
- Requires 30+ days of data

### Max Drawdown
- **< -5%**: Low risk
- **-5% to -10%**: Moderate risk
- **> -10%**: High risk
- Maximum peak-to-trough decline

### Calmar Ratio
- **> 3.0**: Excellent (high return vs drawdown)
- **1.0-3.0**: Good
- **< 1.0**: Poor risk/reward
- Annual return / abs(max drawdown)

### Win Rate
- **> 60%**: Strong
- **50-60%**: Moderate
- **< 50%**: Weak
- Percentage of profitable trades

### Alpha & Beta (vs SPY)
- **Alpha > 0**: Outperforming market
- **Beta < 1**: Less volatile than market
- **Beta > 1**: More volatile than market

## Limitations & Warnings

The system will warn you about:
- **Limited data** (< 30 days): Sharpe ratio may be unreliable
- **Insufficient trades** (< 10): Win rate not statistically significant
- **API failures**: Benchmark comparison unavailable

## Error Handling

All errors are logged and the command uses rollback:
- Failed snapshots are deleted
- Failed report files are cleaned up
- Detailed error messages in logs

## Dependencies

- AlpacaService (for equity history and SPY data)
- GLCommand (command pattern)
- PostgreSQL with JSONB support

## Testing

```bash
# Run all performance reporting tests
bundle exec rspec spec/packs/performance_reporting/

# Run calculator tests only
bundle exec rspec spec/packs/performance_reporting/services/performance_calculator_spec.rb
```

## Future Enhancements

- Email notifications with report summaries
- Web dashboard for visualizing performance
- Multiple strategy comparison
- Risk metrics (VaR, CVaR)
- Trade-level attribution analysis
