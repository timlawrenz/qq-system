# Audit Trail Operations Guide

**Last Updated**: 2025-12-28  
**Owner**: Engineering Team / Operations  
**Related**: [Query Guide](../audit_trail_queries.md), [Architecture](../architecture/trade-outbox-pattern/)

---

## Overview

This guide covers operational procedures for monitoring, troubleshooting, and maintaining the Audit Trail system in production.

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Monitoring & Alerts](#monitoring--alerts)
3. [Incident Response](#incident-response)
4. [Maintenance Tasks](#maintenance-tasks)
5. [Common Issues](#common-issues)
6. [Escalation Procedures](#escalation-procedures)

---

## Daily Operations

### Morning Checklist

Run the daily summary to verify previous trading day:

```bash
# Yesterday's activity
bundle exec rake audit:daily_summary

# Or specific date
bundle exec rake audit:daily_summary[2025-01-15]
```

**Expected Output**:
- ✅ Data ingestion runs completed
- ✅ Trade decisions generated
- ✅ Executions recorded
- ✅ Failure rate < 30%
- ✅ No stuck pending decisions

### Weekly Review

Review strategy performance:

```bash
bundle exec rake audit:strategy_performance
```

**Action Items**:
- Investigate strategies with <50% success rate
- Review failure patterns with failure analysis report
- Check for symbols consistently failing

---

## Monitoring & Alerts

### Critical Alerts

#### 1. Zero Data Ingestion

**Trigger**: No `DataIngestionRun` records created in last 24 hours

**Impact**: Strategies won't have fresh data → no new trades

**Check**:
```ruby
last_run = AuditTrail::DataIngestionRun.order(created_at: :desc).first
hours_ago = ((Time.current - last_run.created_at) / 3600).round(1)
puts "Last ingestion: #{hours_ago} hours ago"

# Alert if > 24 hours
alert! if hours_ago > 24
```

**Resolution**:
1. Check cron jobs: `crontab -l`
2. Check rake task logs
3. Verify API credentials (Alpaca, QuiverQuant)
4. Run manual ingestion: `bundle exec rake data_fetch:congress_daily`

#### 2. High Failure Rate

**Trigger**: >30% of trade decisions fail in a day

**Impact**: Signals not being executed → missed opportunities

**Check**:
```bash
bundle exec rake audit:daily_summary
```

**Resolution**:
1. Run failure analysis: `bundle exec rake audit:failure_analysis`
2. Identify primary failure reason:
   - **Insufficient Buying Power**: Reduce position sizes or add capital
   - **API Rate Limit**: Add backoff/retry logic or reduce frequency
   - **Market Closed**: Check trading hours in strategy
   - **Invalid Symbol**: Update blocked assets list
3. Monitor after fix with: `bundle exec rake audit:strategy_performance`

#### 3. API Errors

**Trigger**: Multiple API responses with 4xx/5xx status codes

**Impact**: Data ingestion or trade execution failures

**Check**:
```ruby
recent_errors = AuditTrail::ApiResponse
  .where('http_status >= 400')
  .where('created_at >= ?', 1.hour.ago)
  .count

alert! if recent_errors > 5
```

**Resolution**:
1. Check API status pages (Alpaca, QuiverQuant)
2. Verify API keys are valid: `bundle exec rails credentials:show -e production`
3. Review rate limits: QuiverQuant = 1,000/day
4. Check for repeated errors:
   ```ruby
   AuditTrail::ApiResponse
     .where('http_status >= 400')
     .where('created_at >= ?', 1.day.ago)
     .group(:http_status)
     .count
   ```

#### 4. Pending Decisions Stuck

**Trigger**: >5 `pending` decisions older than 1 hour

**Impact**: Decisions made but not executed

**Check**:
```ruby
stuck = AuditTrail::TradeDecision
  .pending_decisions
  .where('created_at < ?', 1.hour.ago)
  .count

alert! if stuck > 5
```

**Resolution**:
1. Check if trading is paused
2. Verify job queue is running: `ps aux | grep jobs`
3. Manually execute stuck decisions:
   ```ruby
   stuck_decisions = AuditTrail::TradeDecision
     .pending_decisions
     .where('created_at < ?', 1.hour.ago)
   
   stuck_decisions.each do |decision|
     result = AuditTrail::ExecuteTradeDecision.call(
       trade_decision: decision
     )
     puts "#{decision.decision_id}: #{result.success? ? 'OK' : result.error}"
   end
   ```

### Warning Alerts

#### 1. Low Success Rate for Strategy

**Trigger**: Strategy success rate drops below 50%

**Action**: Review strategy logic, check for data quality issues

**Check**:
```bash
bundle exec rake audit:strategy_performance[CongressionalTradingStrategy]
```

#### 2. Disk Space Growth

**Trigger**: API payloads consuming >10GB

**Action**: Review retention policy, consider purging old data

**Check**:
```bash
bundle exec rake maintenance:storage_stats
```

---

## Incident Response

### Scenario 1: "Trades Not Executing"

**Symptoms**:
- Trade decisions created (`pending`)
- No executions recorded
- Users report missing trades

**Investigation**:
```bash
# 1. Check recent decisions
bundle exec rails runner "
  recent = AuditTrail::TradeDecision.where('created_at >= ?', 1.hour.ago)
  puts \"Total: #{recent.count}\"
  puts \"Pending: #{recent.pending_decisions.count}\"
  puts \"Executed: #{recent.executed_decisions.count}\"
  puts \"Failed: #{recent.failed_decisions.count}\"
"

# 2. Check for execution errors
bundle exec rails runner "
  failed = AuditTrail::TradeExecution
    .where('created_at >= ?', 1.hour.ago)
    .where(status: 'rejected')
  
  failed.each do |exec|
    puts \"#{exec.execution_id}: #{exec.error_message}\"
  end
"
```

**Resolution**:
1. If all pending: Check job queue, verify Alpaca API connectivity
2. If all failed: Check error messages, likely buying power or API issue
3. If mixed: Isolated failures, investigate per-symbol

### Scenario 2: "Missing Data"

**Symptoms**:
- Ingestion run reports 0 records fetched
- Strategies not generating decisions
- Source data is stale

**Investigation**:
```bash
# 1. Check ingestion runs
bundle exec rails runner "
  runs = AuditTrail::DataIngestionRun.where('created_at >= ?', 1.day.ago)
  runs.each do |run|
    puts \"#{run.task_name} | #{run.created_at} | Fetched: #{run.records_fetched}\"
  end
"

# 2. Check API call logs
bundle exec rails runner "
  logs = AuditTrail::ApiCallLog
    .where('created_at >= ?', 1.day.ago)
    .includes(:api_response_payload)
  
  logs.each do |log|
    resp = log.api_response_payload
    puts \"#{log.endpoint} | Status: #{resp.http_status}\"
  end
"
```

**Resolution**:
1. Verify QuiverQuant API key: `QUIVER_API_KEY` in credentials
2. Check rate limits: 1,000 calls/day on Trader tier
3. Test API manually:
   ```bash
   curl -H "Authorization: Token YOUR_KEY" \
     https://api.quiverquant.com/beta/live/congresstrading
   ```
4. Re-run ingestion: `bundle exec rake data_fetch:congress_daily`

### Scenario 3: "Duplicate Trades"

**Symptoms**:
- Multiple executions for same decision
- Unexpected positions in account

**Investigation**:
```bash
# Find decisions with multiple executions
bundle exec rails runner "
  duplicates = AuditTrail::TradeDecision
    .joins(:trade_executions)
    .group('trade_decisions.id')
    .having('COUNT(trade_executions.id) > 1')
  
  duplicates.each do |decision|
    puts \"Decision: #{decision.decision_id}\"
    decision.trade_executions.each do |exec|
      puts \"  Execution: #{exec.execution_id} | #{exec.status}\"
    end
  end
"
```

**Resolution**:
1. This should not happen (system prevents it)
2. Check for race conditions in execution logic
3. Cancel duplicate orders via Alpaca dashboard
4. File bug report with execution IDs

---

## Maintenance Tasks

### Monthly: Storage Cleanup

Run retention policy (keep 2 years):

```bash
bundle exec rake maintenance:purge_old_api_payloads
```

**Timing**: First Sunday of month at 2 AM (via cron)

**Expected**: ~1,000-5,000 records deleted (depends on activity)

### Weekly: Performance Review

```bash
# 1. Strategy performance
bundle exec rake audit:strategy_performance

# 2. Failure trends
bundle exec rake audit:failure_analysis

# 3. Storage stats
bundle exec rake maintenance:storage_stats
```

**Action Items**:
- Update position sizing if failures due to buying power
- Adjust strategy parameters if success rate declining
- Plan for storage if growing rapidly

### Quarterly: Full Audit

1. **Data Integrity**:
   ```ruby
   # Verify all decisions have rationale
   missing = AuditTrail::TradeDecision.where(decision_rationale: {})
   puts "Missing rationale: #{missing.count} (should be 0)"
   
   # Verify all executions have API payloads
   missing_api = AuditTrail::TradeExecution
     .where(api_request_payload_id: nil)
     .or(AuditTrail::TradeExecution.where(api_response_payload_id: nil))
   puts "Missing API payloads: #{missing_api.count} (should be 0)"
   ```

2. **Performance Review**:
   - Export quarterly report for stakeholders
   - Compare strategy performance trends
   - Identify optimization opportunities

3. **Compliance Check**:
   - Verify audit trail completeness
   - Test data lineage queries
   - Document any gaps or issues

---

## Common Issues

### Issue: Slow Queries

**Symptom**: Audit reports take >5 seconds

**Cause**: Missing indexes, N+1 queries, large date ranges

**Fix**:
1. Check indexes: `bundle exec rails db:migrate:status`
2. Use `includes()` in queries (see [Query Guide](../audit_trail_queries.md))
3. Reduce date range or add pagination

### Issue: JSONB Query Errors

**Symptom**: `PG::UndefinedFunction: ERROR: operator does not exist`

**Cause**: Missing GIN index on JSONB column

**Fix**:
```sql
-- Verify indexes exist
SELECT tablename, indexname 
FROM pg_indexes 
WHERE tablename IN ('trade_decisions', 'api_payloads');

-- Should see:
-- index_trade_decisions_on_decision_rationale
-- index_api_payloads_on_payload
```

### Issue: Orphaned Records

**Symptom**: Decisions without executions, executions without decisions

**Check**:
```ruby
# Decisions pending forever
old_pending = AuditTrail::TradeDecision
  .pending_decisions
  .where('created_at < ?', 1.week.ago)

puts "Old pending decisions: #{old_pending.count}"

# Executions without decisions (should never happen)
orphans = AuditTrail::TradeExecution
  .where.not(trade_decision_id: AuditTrail::TradeDecision.select(:id))

puts "Orphaned executions: #{orphans.count}"
```

**Fix**:
- Old pending: Likely cancelled by user or system, mark as `cancelled`
- Orphans: Data integrity issue, investigate before deleting

---

## Escalation Procedures

### Level 1: On-Call Engineer

**Handles**:
- Zero data ingestion (run manual fetch)
- High failure rate (check buying power)
- API errors (verify credentials)
- Slow queries (check indexes)

**Escalate to Level 2 if**:
- Issue persists after standard fixes
- Data integrity concerns (orphaned records, missing data)
- System-wide outage (all strategies failing)

### Level 2: Senior Engineer

**Handles**:
- Database performance issues
- Complex data lineage investigations
- Strategy logic bugs
- API integration failures

**Escalate to Level 3 if**:
- Security concerns (unauthorized trades)
- Regulatory inquiry
- Critical bug requiring immediate patch

### Level 3: Engineering Lead + Legal

**Handles**:
- Regulatory audits
- Security incidents
- Critical production bugs
- Emergency rollbacks

---

## Configuration

### Environment Variables

Production:
```bash
# Required
ALPACA_API_KEY=...
ALPACA_API_SECRET=...
QUIVER_API_KEY=...

# Optional
AUDIT_RETENTION_DAYS=730  # 2 years
ALERT_EMAIL=alerts@example.com
SLACK_WEBHOOK_URL=...
```

### Cron Jobs

```cron
# Daily maintenance (2 AM)
0 2 * * * cd /app && bundle exec rake maintenance:daily

# Daily summary email (9 AM)
0 9 * * * cd /app && bundle exec rake audit:daily_summary | mail -s "Daily Summary" team@example.com

# Monthly cleanup (first Sunday, 2 AM)
0 2 1-7 * 0 cd /app && bundle exec rake maintenance:purge_old_api_payloads
```

---

## Runbook Checklist

### Before Production Deployment

- [ ] Run full test suite
- [ ] Verify all indexes exist
- [ ] Test rake tasks in staging
- [ ] Configure alerts
- [ ] Set up cron jobs
- [ ] Document rollback plan

### During Incident

- [ ] Identify scope (single strategy, all strategies, etc.)
- [ ] Check recent changes (deployments, config)
- [ ] Review logs and error messages
- [ ] Document timeline and actions taken
- [ ] Communicate status to stakeholders
- [ ] Follow escalation procedures

### After Incident

- [ ] Post-mortem document
- [ ] Update runbook with new learnings
- [ ] Add monitoring for similar issues
- [ ] Test fixes in staging
- [ ] Deploy fixes to production
- [ ] Verify resolution

---

## Useful Commands Reference

```bash
# Rails console
bundle exec rails console -e production

# Run specific rake task
bundle exec rake audit:symbol_report[AAPL,2025-01-01,2025-12-31]

# Check job queue
ps aux | grep jobs
bundle exec rails runner "puts SolidQueue::Job.count"

# Database query
psql $DATABASE_URL -c "SELECT COUNT(*) FROM trade_decisions WHERE created_at >= NOW() - INTERVAL '1 day'"

# Tail logs
tail -f log/production.log | grep -E "TradeDecision|TradeExecution"
```

---

## See Also

- [Query Guide](../audit_trail_queries.md) - SQL and Ruby queries
- [Architecture](../architecture/trade-outbox-pattern/) - System design
- [Monitoring Dashboard](#) - (TODO: Link to dashboard when created)
- [API Documentation](../../README.md) - Rails API endpoints
