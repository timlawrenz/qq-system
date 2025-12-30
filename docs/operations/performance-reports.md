# Performance Reports Operations Guide

## Setup

### 1. Database Migration

Ensure the performance_snapshots table exists:

```bash
bundle exec rails db:migrate
```

### 2. Cron Configuration

Add to your crontab (`crontab -e`):

```cron
# Weekly Performance Report (Sunday at 11:00 PM EST)
0 23 * * 0 cd /home/tim/source/activity/qq-system && rvm use && TRADING_MODE=paper bundle exec rake performance:weekly_report >> log/weekly_paper_$(date +\%Y\%m\%d).log 2>&1
0 23 * * 0 cd /home/tim/source/activity/qq-system && rvm use && TRADING_MODE=live CONFIRM_LIVE_TRADING=yes bundle exec rake performance:weekly_report >> log/weekly_live_$(date +\%Y\%m\%d).log 2>&1

# (Alternative) Use the script wrapper
# TRADING_MODE=paper ./weekly_performance_report.sh
# TRADING_MODE=live CONFIRM_LIVE_TRADING=yes ./weekly_performance_report.sh
```

### 3. Log Directory

Ensure log directory exists:

```bash
mkdir -p log
```

## Running Reports

### Manual Execution

```bash
# Run weekly report via rake task (recommended)
TRADING_MODE=paper bundle exec rake performance:weekly_report

# Or via script wrapper
TRADING_MODE=paper ./weekly_performance_report.sh

# Or via Rails runner (advanced)
bundle exec rails runner "
  result = GeneratePerformanceReport.call(strategy_name: 'Blended Portfolio (paper)')
  puts result.file_path if result.success?
"
```

### Check Last Report

```bash
# View today's JSON reports
ls -lh tmp/performance_reports/$(date +%F)*.json

# Inspect one
jq . tmp/performance_reports/$(date +%F)-blended-portfolio-paper.json | head

# Check database
bundle exec rails runner "
  snapshot = PerformanceSnapshot.order(created_at: :desc).first
  puts snapshot.inspect
"
```

## Monitoring

### Check Cron Logs

```bash
# View latest weekly report log
tail -100 log/weekly_$(date +%Y%m%d).log

# Search for errors
grep -i error log/weekly_*.log
```

### Verify Reports Generated

```bash
# List all report files
ls -lh tmp/performance_reports/

# Count snapshots in database
bundle exec rails runner "
  puts \"Total snapshots: #{PerformanceSnapshot.count}\"
  puts \"Weekly snapshots: #{PerformanceSnapshot.weekly.count}\"
  puts \"Last snapshot: #{PerformanceSnapshot.order(:snapshot_date).last&.snapshot_date}\"
"
```

## Troubleshooting

### Report Generation Fails

**Check Alpaca API connectivity:**
```bash
bundle exec rails runner "
  service = AlpacaService.new
  puts service.account_equity
"
```

**Check for missing equity history:**
```bash
bundle exec rails runner "
  service = AlpacaService.new
  history = service.account_equity_history(start_date: 30.days.ago.to_date)
  puts \"Data points: #{history.count}\"
"
```

### Insufficient Data Warnings

If you see "Limited data" warnings:
- Normal for new accounts (< 30 days trading)
- Sharpe ratio requires 30+ days of daily returns
- Win rate requires 10+ trades
- Reports still generate, just with nil values for some metrics

### Missing Reports in Database

```bash
# Check for orphaned snapshots
bundle exec rails runner "
  PerformanceSnapshot.where('created_at < ?', 7.days.ago).destroy_all
"
```

### Clean Up Old Reports

```bash
# Remove report files older than 90 days
find tmp/performance_reports -name "performance_*.json" -mtime +90 -delete

# Archive old snapshots (optional)
bundle exec rails runner "
  old_snapshots = PerformanceSnapshot.where('snapshot_date < ?', 1.year.ago)
  puts \"Archiving #{old_snapshots.count} snapshots\"
  # Export to CSV or backup before deleting
  old_snapshots.destroy_all
"
```

## Metrics to Watch

### Weekly Checklist

- [ ] Report generated successfully
- [ ] Equity value matches Alpaca account
- [ ] Sharpe ratio calculated (if > 30 days data)
- [ ] Max drawdown reasonable (< -20%)
- [ ] Win rate > 50%
- [ ] Alpha vs SPY available

### Alert Thresholds

Set up alerts if:
- **Max drawdown > -15%**: Review strategy immediately
- **Sharpe ratio < 0**: Strategy underperforming risk-free rate
- **Win rate < 40%**: Strategy may need adjustment
- **Report generation fails 2+ weeks**: Check system health

## Performance Analysis

### Compare Strategies

```ruby
# Get performance across strategies
PerformanceSnapshot.weekly
  .where(snapshot_date: Date.current)
  .group(:strategy_name)
  .pluck(:strategy_name, :sharpe_ratio, :max_drawdown_pct)
```

### Track Improvement

```ruby
# Get last 12 weeks
snapshots = PerformanceSnapshot.weekly
  .by_strategy('Enhanced Congressional')
  .where('snapshot_date >= ?', 12.weeks.ago.to_date)
  .order(:snapshot_date)

# Calculate trend
sharpes = snapshots.pluck(:sharpe_ratio).compact
if sharpes.size >= 4
  recent_avg = sharpes.last(4).sum / 4.0
  older_avg = sharpes.first(4).sum / 4.0
  improvement = ((recent_avg - older_avg) / older_avg * 100).round(2)
  puts "Sharpe improvement: #{improvement}%"
end
```

## Backup & Recovery

### Backup Reports

```bash
# Backup report files
tar -czf performance_reports_backup_$(date +%Y%m%d).tar.gz tmp/performance_reports/

# Backup database snapshots
bundle exec rails runner "
  require 'csv'
  CSV.open('snapshots_backup.csv', 'w') do |csv|
    csv << PerformanceSnapshot.column_names
    PerformanceSnapshot.find_each do |s|
      csv << s.attributes.values
    end
  end
"
```

### Restore Snapshot

```ruby
# If report generation fails, snapshot is automatically rolled back
# Manual rollback if needed:
PerformanceSnapshot.find(snapshot_id).destroy
File.delete(file_path) if File.exist?(file_path)
```

## Integration with Other Systems

### Email Notifications (Future)

```ruby
# Example: Send email with report
if result.success?
  PerformanceMailer.weekly_report(
    email: 'your@email.com',
    report: result.report_hash
  ).deliver_later
end
```

### Slack Notifications (Future)

```ruby
# Post summary to Slack
SlackNotifier.notify(
  channel: '#trading-alerts',
  message: "Weekly Report: P&L $#{pnl}, Sharpe #{sharpe}"
)
```

## Maintenance Schedule

- **Daily**: Check cron logs for errors
- **Weekly**: Review generated reports
- **Monthly**: Clean up old report files
- **Quarterly**: Review and archive old snapshots
- **Annually**: Backup all historical data

## Support

For issues or questions:
1. Check error logs in `log/weekly_*.log`
2. Review this operations guide
3. Test components individually (calculator, service, command)
4. Check Alpaca API status
