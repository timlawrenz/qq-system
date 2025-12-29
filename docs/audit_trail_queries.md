# Audit Trail Query Guide

**Last Updated**: 2025-12-28  
**Owner**: Engineering Team  
**Related**: [Trade Outbox Pattern](architecture/trade-outbox-pattern/), [Operations Guide](operations/audit_trail.md)

---

## Overview

The Audit Trail system provides comprehensive logging of all data ingestion, trade decisions, and executions. This guide shows common queries and analysis patterns.

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Symbol Activity Analysis](#symbol-activity-analysis)
3. [Strategy Performance Analysis](#strategy-performance-analysis)
4. [Failure Analysis](#failure-analysis)
5. [Data Lineage Queries](#data-lineage-queries)
6. [Compliance Queries](#compliance-queries)
7. [Performance Optimization](#performance-optimization)

---

## Quick Reference

### Rake Tasks

```bash
# Symbol activity report
rake audit:symbol_report[AAPL,2025-01-01,2025-12-31]
SYMBOL=AAPL START_DATE=2025-01-01 rake audit:symbol_report

# Strategy performance
rake audit:strategy_performance
rake audit:strategy_performance[CongressionalTradingStrategy]

# Daily summary
rake audit:daily_summary
rake audit:daily_summary[2025-01-15]

# Failure analysis
rake audit:failure_analysis
rake audit:failure_analysis[2025-01-01,2025-01-31,CongressionalTradingStrategy]

# Maintenance
rake maintenance:storage_stats
rake maintenance:purge_old_api_payloads
```

### Ruby Console Queries

```ruby
# Generate reports programmatically
report = AuditTrail::SymbolActivityReport.generate(
  symbol: 'AAPL',
  start_date: '2025-01-01',
  end_date: '2025-12-31'
)

performance = AuditTrail::StrategyPerformanceReport.generate(
  strategy_name: 'CongressionalTradingStrategy'
)

failures = AuditTrail::FailureAnalysisReport.generate(
  start_date: 7.days.ago,
  end_date: Date.current
)
```

---

## Symbol Activity Analysis

### Show All Activity for a Symbol

**Use Case**: "What happened with AAPL in Q1 2025?"

```bash
rake audit:symbol_report[AAPL,2025-01-01,2025-03-31]
```

**Output**:
- Data ingested (congressional/insider trades)
- Decisions made by strategies
- Trades executed
- Success rate

### Find All Decisions for a Symbol

```ruby
# Console query
decisions = AuditTrail::TradeDecision
  .for_symbol('AAPL')
  .where(created_at: 1.month.ago..Date.current)
  .includes(:trade_executions)
  .order(created_at: :desc)

decisions.each do |d|
  puts "#{d.created_at} | #{d.strategy_name} | #{d.side} #{d.quantity} | #{d.status}"
end
```

### Trace Decision to Source Data

**Use Case**: "What QuiverTrade triggered this decision?"

```ruby
decision = AuditTrail::TradeDecision.find_by(decision_id: 'abc123')

# Primary source
quiver_trade = decision.primary_quiver_trade
puts "Source: #{quiver_trade.trader_name} | #{quiver_trade.transaction_date}"

# Ingestion run
ingestion_run = decision.primary_ingestion_run
puts "Fetched: #{ingestion_run.created_at} | #{ingestion_run.task_name}"

# Full rationale (includes all source IDs)
puts decision.decision_rationale
```

---

## Strategy Performance Analysis

### Compare All Strategies

```bash
rake audit:strategy_performance
```

**Output**: Table showing signals, executions, failures, success rate per strategy

### Analyze Single Strategy

```bash
rake audit:strategy_performance[CongressionalTradingStrategy]
```

### Strategy Success Rate Over Time

```ruby
# Group by week
AuditTrail::TradeDecision
  .where(strategy_name: 'CongressionalTradingStrategy')
  .group_by_week(:created_at)
  .group(:status)
  .count
  .transform_keys { |week, status| [week.to_date, status] }
```

### Compare Signal Quality vs Execution Issues

**Use Case**: "Are failures due to bad signals or execution problems?"

```ruby
strategy = 'CongressionalTradingStrategy'

# Signal quality (decisions generated)
total_decisions = AuditTrail::TradeDecision.where(strategy_name: strategy).count

# Execution attempts
attempted = AuditTrail::TradeExecution
  .joins(:trade_decision)
  .where(trade_decisions: { strategy_name: strategy })
  .count

# Success rate
filled = AuditTrail::TradeExecution
  .joins(:trade_decision)
  .where(trade_decisions: { strategy_name: strategy })
  .where(status: 'filled')
  .count

puts "Total signals: #{total_decisions}"
puts "Execution attempts: #{attempted} (#{(attempted.to_f / total_decisions * 100).round(1)}%)"
puts "Successfully filled: #{filled} (#{(filled.to_f / attempted * 100).round(1)}%)"
```

---

## Failure Analysis

### Identify Failure Patterns

```bash
rake audit:failure_analysis[2025-01-01,2025-01-31]
```

**Output**:
- Failure rate
- Failures by reason (insufficient buying power, API errors, etc.)
- Top failing symbols
- Top error messages

### Find All Insufficient Buying Power Failures

```ruby
failures = AuditTrail::TradeExecution
  .where(status: 'rejected')
  .where("error_message ILIKE ?", "%insufficient%buying%power%")
  .includes(trade_decision: :primary_quiver_trade)

failures.each do |exec|
  decision = exec.trade_decision
  puts "#{decision.symbol} | #{decision.side} #{decision.quantity} @ #{decision.limit_price}"
  puts "  Rationale: #{decision.decision_rationale['explanation']}"
  puts "  Error: #{exec.error_message}"
  puts
end
```

### API Error Analysis

```ruby
# Group API errors by type
api_errors = AuditTrail::ApiResponse
  .where('http_status >= ?', 400)
  .group(:http_status)
  .count

puts "API Errors:"
api_errors.each do |status, count|
  puts "  #{status}: #{count} errors"
end

# Most recent API errors
recent_errors = AuditTrail::ApiResponse
  .where('http_status >= ?', 400)
  .order(created_at: :desc)
  .limit(10)

recent_errors.each do |resp|
  log = resp.api_call_logs.first
  puts "#{resp.created_at} | #{log&.endpoint} | #{resp.http_status}"
  puts "  #{resp.payload['error']}"
end
```

---

## Data Lineage Queries

### Complete Trade Lineage

**Use Case**: "Show full history from data fetch → decision → execution"

```ruby
# Start with a trade execution
execution = AuditTrail::TradeExecution.find_by(execution_id: 'exec-abc123')

# Trace backwards
decision = execution.trade_decision
quiver_trade = decision.primary_quiver_trade
ingestion_run = decision.primary_ingestion_run

puts "📊 Trade Lineage:"
puts "─" * 60
puts "1️⃣ Data Fetched:"
puts "   Ingestion: #{ingestion_run.task_name} at #{ingestion_run.created_at}"
puts "   Records: #{ingestion_run.records_fetched} fetched, #{ingestion_run.records_created} created"
puts
puts "2️⃣ Source Data:"
puts "   Trader: #{quiver_trade.trader_name}"
puts "   Transaction: #{quiver_trade.transaction_type} #{quiver_trade.ticker} on #{quiver_trade.transaction_date}"
puts "   Size: $#{quiver_trade.trade_size_usd}"
puts
puts "3️⃣ Decision Made:"
puts "   Strategy: #{decision.strategy_name}"
puts "   Action: #{decision.side.upcase} #{decision.quantity} #{decision.symbol} @ #{decision.limit_price}"
puts "   Created: #{decision.created_at}"
puts "   Rationale: #{decision.decision_rationale['explanation']}"
puts
puts "4️⃣ Execution:"
puts "   Status: #{execution.status}"
puts "   Filled: #{execution.filled_quantity} @ $#{execution.filled_avg_price}"
puts "   Alpaca Order: #{execution.alpaca_order_id}"
puts "   Executed: #{execution.created_at}"
```

### Find All Decisions from a Data Fetch

**Use Case**: "What trades resulted from today's congressional data fetch?"

```ruby
# Find ingestion run
run = AuditTrail::DataIngestionRun
  .where(task_name: 'data_fetch:congress_daily')
  .where('created_at >= ?', Date.current.beginning_of_day)
  .last

# Find related decisions
decisions = AuditTrail::TradeDecision.where(primary_ingestion_run: run)

puts "Ingestion Run: #{run.task_name} at #{run.created_at}"
puts "Records: #{run.records_fetched} fetched, #{run.records_created} new"
puts "Decisions Generated: #{decisions.count}"
puts
decisions.each do |d|
  puts "  #{d.strategy_name} | #{d.side} #{d.quantity} #{d.symbol} | #{d.status}"
end
```

---

## Compliance Queries

### Prove Data Timeliness

**Use Case**: "When did we first have data about this trade?"

```ruby
symbol = 'AAPL'
decision_time = Time.zone.parse('2025-01-15 14:30:00')

# Find all QuiverTrades we had before decision
available_data = QuiverTrade
  .for_ticker(symbol)
  .where('created_at < ?', decision_time)
  .order(transaction_date: :desc)

puts "Data Available Before Decision (#{decision_time}):"
available_data.each do |qt|
  puts "  #{qt.transaction_date} | #{qt.trader_name} | Ingested: #{qt.created_at}"
end
```

### Audit Trail for Regulatory Review

**Use Case**: "Provide audit trail for SEC/FINRA review"

```ruby
# For a specific decision
decision = AuditTrail::TradeDecision.find_by(decision_id: 'abc123')

audit_report = {
  decision_id: decision.decision_id,
  decision_timestamp: decision.created_at.iso8601,
  strategy: decision.strategy_name,
  action: "#{decision.side.upcase} #{decision.quantity} #{decision.symbol}",
  
  source_data: {
    quiver_trade_id: decision.primary_quiver_trade&.id,
    trader: decision.primary_quiver_trade&.trader_name,
    transaction_date: decision.primary_quiver_trade&.transaction_date,
    data_ingested_at: decision.primary_ingestion_run&.created_at&.iso8601
  },
  
  rationale: decision.decision_rationale,
  
  execution: decision.trade_executions.map do |exec|
    {
      execution_id: exec.execution_id,
      status: exec.status,
      filled_qty: exec.filled_quantity,
      filled_price: exec.filled_avg_price,
      alpaca_order: exec.alpaca_order_id,
      timestamp: exec.created_at.iso8601
    }
  end
}

puts JSON.pretty_generate(audit_report)
```

---

## Performance Optimization

### Common Query Patterns

```ruby
# ✅ GOOD: Preload associations
AuditTrail::TradeDecision
  .includes(:trade_executions, :primary_quiver_trade, :primary_ingestion_run)
  .where(symbol: 'AAPL')
  .each { |d| puts d.trade_executions.first&.status }

# ❌ BAD: N+1 queries
AuditTrail::TradeDecision
  .where(symbol: 'AAPL')
  .each { |d| puts d.trade_executions.first&.status } # N+1!
```

### Index Usage

All audit trail tables have proper indexes:
- `trade_decisions`: symbol, strategy_name, status, created_at
- `trade_executions`: status, created_at
- `data_ingestion_runs`: task_name, created_at
- JSONB fields: GIN indexes on decision_rationale, api payload

### Query Performance Targets

- Symbol activity report: <200ms
- Strategy performance: <500ms
- Failure analysis: <1s for 1 month
- Data lineage: <100ms (single trade)

---

## Advanced Patterns

### Custom Aggregations

```ruby
# Success rate by day of week
results = AuditTrail::TradeDecision
  .select("EXTRACT(DOW FROM created_at) as dow, status, COUNT(*)")
  .group("EXTRACT(DOW FROM created_at), status")
  .order("dow")

by_day = results.group_by(&:dow)
by_day.each do |day, records|
  total = records.sum(&:count)
  executed = records.find { |r| r.status == 'executed' }&.count || 0
  rate = (executed.to_f / total * 100).round(1)
  puts "Day #{day}: #{executed}/#{total} (#{rate}%)"
end
```

### Time-Series Analysis

```ruby
# Rolling 7-day success rate
require 'date'

(30.days.ago.to_date..Date.current).each do |date|
  window_start = date - 6.days
  window_end = date
  
  decisions = AuditTrail::TradeDecision
    .where(created_at: window_start.beginning_of_day..window_end.end_of_day)
  
  total = decisions.count
  executed = decisions.where(status: 'executed').count
  rate = total.positive? ? (executed.to_f / total * 100).round(1) : 0
  
  puts "#{date}: #{rate}% (#{executed}/#{total})"
end
```

---

## Troubleshooting

### Slow Queries

If queries are slow:

1. **Check for N+1 queries**: Use `includes()` or `eager_load()`
2. **Verify indexes**: Run `EXPLAIN ANALYZE` in psql
3. **Reduce date ranges**: Limit to necessary time period
4. **Use counts**: Prefer `.count` over `.size` or `.length`

### Missing Data

If audit trail data is missing:

```ruby
# Check ingestion runs
recent_runs = AuditTrail::DataIngestionRun
  .where('created_at >= ?', 7.days.ago)
  .order(created_at: :desc)

puts "Recent Ingestion Runs:"
recent_runs.each do |run|
  puts "#{run.task_name} | #{run.created_at} | #{run.records_fetched} fetched"
end

# Check for zero-record runs (possible failures)
zero_runs = recent_runs.where(records_fetched: 0)
puts "\nWarning: #{zero_runs.count} runs fetched zero records"
```

---

## See Also

- [Trade Outbox Pattern Architecture](architecture/trade-outbox-pattern/)
- [Operations Guide](operations/audit_trail.md)
- [API Documentation](../README.md)
