# OpenSpec Proposal: FetchQuiverData Command & Job

## Metadata
- **Title**: Implement FetchQuiverData Command and FetchQuiverDataJob
- **Author**: GitHub Copilot
- **Date**: 2025-11-04
- **Status**: Proposal
- **Priority**: Critical (Blocks paper trading)
- **Estimated Effort**: 4-6 hours

---

## Problem Statement

The trading system currently lacks the ability to fetch fresh congressional trading data from the QuiverQuant API and persist it to the database. This creates a critical gap in the data pipeline:

**Current State:**
```
❌ QuiverQuant API
   ↓ (MISSING!)
❌ QuiverTrade database table
   ↓
✅ GenerateTargetPortfolio (reads from DB)
   ↓
✅ RebalanceToTarget (executes trades)
```

**Impact:**
- ExecuteSimpleStrategyJob reads from QuiverTrade table, but nothing populates it
- Paper trading cannot start without fresh data
- Manual data imports are not sustainable for production

---

## Goals

1. **Primary**: Build FetchQuiverData command to fetch and persist congressional trade data
2. **Secondary**: Build FetchQuiverDataJob to automate the data fetch process
3. **Tertiary**: Enable paper trading to start immediately after implementation

**Success Criteria:**
- FetchQuiverDataJob runs successfully and populates QuiverTrade table
- Data is deduplicated (no duplicate trades)
- Errors are handled gracefully with clear logging
- Manual testing validates end-to-end flow works

---

## Technical Design

### Component 1: FetchQuiverData Command

**Location**: `packs/data_fetching/app/commands/fetch_quiver_data.rb`

**Responsibility**: Fetch congressional trades from QuiverQuant API and persist to database

**Interface:**
```ruby
class FetchQuiverData < GLCommand::Callable
  allows :start_date, :end_date, :ticker
  returns :trades_count, :new_trades_count, :updated_trades_count, :error_count
  
  def call
    # Implementation
  end
end
```

**Parameters:**
- `start_date` (Date, optional): Fetch trades from this date. Default: 60 days ago
- `end_date` (Date, optional): Fetch trades until this date. Default: today
- `ticker` (String, optional): Filter by specific ticker. Default: all tickers

**Returns:**
- `trades_count` (Integer): Total trades fetched from API
- `new_trades_count` (Integer): Number of new trades saved to database
- `updated_trades_count` (Integer): Number of existing trades updated
- `error_count` (Integer): Number of trades that failed to save

**Algorithm:**

```ruby
def call
  # Step 1: Initialize counters
  context.trades_count = 0
  context.new_trades_count = 0
  context.updated_trades_count = 0
  context.error_count = 0
  
  # Step 2: Fetch from API using existing QuiverClient
  trades_data = fetch_from_api
  context.trades_count = trades_data.size
  
  # Step 3: Process each trade (save or update)
  trades_data.each do |trade_attrs|
    process_trade(trade_attrs)
  end
  
  # Step 4: Log summary
  log_summary
  
  context
end

private

def fetch_from_api
  client = QuiverClient.new
  client.fetch_congressional_trades(
    start_date: context.start_date || 60.days.ago.to_date,
    end_date: context.end_date || Date.today,
    ticker: context.ticker
  )
rescue StandardError => e
  Rails.logger.error("FetchQuiverData: API fetch failed: #{e.message}")
  stop_and_fail!("Failed to fetch data from Quiver API: #{e.message}")
end

def process_trade(trade_attrs)
  # Find or create based on unique composite key
  trade = QuiverTrade.find_or_initialize_by(
    ticker: trade_attrs[:ticker],
    trader_name: trade_attrs[:trader_name],
    transaction_date: trade_attrs[:transaction_date]
  )
  
  is_new = trade.new_record?
  
  # Assign attributes
  trade.assign_attributes(
    company: trade_attrs[:company],
    trader_source: trade_attrs[:trader_source],
    transaction_type: trade_attrs[:transaction_type],
    trade_size_usd: trade_attrs[:trade_size_usd],
    disclosed_at: trade_attrs[:disclosed_at]
  )
  
  # Save if new or changed
  if trade.changed?
    trade.save!
    if is_new
      context.new_trades_count += 1
    else
      context.updated_trades_count += 1
    end
  end
  
rescue StandardError => e
  context.error_count += 1
  Rails.logger.error(
    "FetchQuiverData: Failed to save trade #{trade_attrs[:ticker]}/#{trade_attrs[:trader_name]}: #{e.message}"
  )
  # Continue processing other trades
end

def log_summary
  Rails.logger.info(
    "FetchQuiverData: Processed #{context.trades_count} trades - " \
    "#{context.new_trades_count} new, " \
    "#{context.updated_trades_count} updated, " \
    "#{context.error_count} errors"
  )
end
```

**Error Handling:**
- API fetch failures → Fail command immediately (stop_and_fail!)
- Individual trade save failures → Log error, continue with remaining trades
- All errors logged with context for debugging

**Edge Cases:**
1. Empty API response → Return success with 0 trades
2. Duplicate trades → Use find_or_initialize_by to handle
3. Invalid date formats → Log warning, skip that trade
4. Missing required fields → Log error, skip that trade
5. Database connection issues → Fail entire command (transaction rollback)

---

### Component 2: FetchQuiverDataJob

**Location**: `packs/data_fetching/app/jobs/fetch_quiver_data_job.rb`

**Responsibility**: Background job wrapper for FetchQuiverData command

**Interface:**
```ruby
class FetchQuiverDataJob < ApplicationJob
  queue_as :default
  
  def perform(start_date: nil, end_date: nil, ticker: nil)
    # Implementation
  end
end
```

**Parameters:**
- Same as FetchQuiverData command (all optional)
- When called without parameters, fetches last 60 days of data

**Implementation:**

```ruby
class FetchQuiverDataJob < ApplicationJob
  queue_as :default
  
  # Retry configuration
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(start_date: nil, end_date: nil, ticker: nil)
    Rails.logger.info("=" * 80)
    Rails.logger.info("FetchQuiverDataJob: Starting data fetch")
    Rails.logger.info("  start_date: #{start_date || '60 days ago'}")
    Rails.logger.info("  end_date: #{end_date || 'today'}")
    Rails.logger.info("  ticker: #{ticker || 'all'}")
    Rails.logger.info("=" * 80)
    
    # Call the command
    result = FetchQuiverData.call(
      start_date: start_date,
      end_date: end_date,
      ticker: ticker
    )
    
    # Handle result
    if result.success?
      Rails.logger.info(
        "FetchQuiverDataJob: SUCCESS - " \
        "Fetched #{result.trades_count} trades " \
        "(#{result.new_trades_count} new, #{result.updated_trades_count} updated)"
      )
      
      # Alert if high error rate
      if result.error_count > 0
        error_rate = (result.error_count.to_f / result.trades_count * 100).round(1)
        Rails.logger.warn(
          "FetchQuiverDataJob: #{result.error_count} trades failed to save (#{error_rate}% error rate)"
        )
      end
    else
      Rails.logger.error("FetchQuiverDataJob: FAILED - #{result.error}")
      raise result.error # Re-raise to mark job as failed for retry
    end
    
    Rails.logger.info("=" * 80)
    Rails.logger.info("FetchQuiverDataJob: Complete")
    Rails.logger.info("=" * 80)
    
  rescue StandardError => e
    Rails.logger.error("FetchQuiverDataJob: Unexpected error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise # Re-raise for retry mechanism
  end
end
```

**Retry Strategy:**
- 3 attempts with exponential backoff (1s, 2s, 4s)
- Retries on any StandardError
- Logs each retry attempt
- Marks job as failed after all retries exhausted

**Monitoring:**
- Logs include clear SUCCESS/FAILED markers for easy filtering
- Structured logging with counts for metrics tracking
- Warnings for high error rates (>5%)

---

## Database Schema

**No changes required** - QuiverTrade model already exists with correct schema:

```ruby
# Schema for quiver_trades table
create_table "quiver_trades" do |t|
  t.string "ticker"
  t.string "company"
  t.string "trader_name"
  t.string "trader_source"
  t.date "transaction_date"
  t.string "transaction_type"
  t.string "trade_size_usd"
  t.datetime "disclosed_at"
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
end
```

**Composite Unique Key** (for deduplication):
- `ticker` + `trader_name` + `transaction_date`

**Rationale**: Same person can trade same stock on different dates, but unlikely to have duplicate trades on same date.

**Index Recommendations** (optional, for performance):
```ruby
# Add in future migration if needed
add_index :quiver_trades, [:ticker, :trader_name, :transaction_date], 
          unique: true, 
          name: 'index_quiver_trades_unique'
add_index :quiver_trades, :transaction_date
add_index :quiver_trades, :created_at
```

---

## Testing Strategy

### Unit Tests

**Test File**: `spec/packs/data_fetching/commands/fetch_quiver_data_spec.rb`

**Test Cases:**

1. **Success Path:**
   - Fetches trades from API successfully
   - Saves new trades to database
   - Returns correct counts
   - Logs summary message

2. **Deduplication:**
   - Does not create duplicate trades
   - Updates existing trades if data changed
   - Leaves unchanged trades alone

3. **Error Handling:**
   - Handles API failure gracefully
   - Continues processing after individual trade save error
   - Returns error count correctly

4. **Edge Cases:**
   - Empty API response returns success with 0 trades
   - Handles nil dates gracefully
   - Handles missing optional fields

**Test File**: `spec/packs/data_fetching/jobs/fetch_quiver_data_job_spec.rb`

**Test Cases:**

1. **Job Execution:**
   - Calls FetchQuiverData command with correct params
   - Logs success message
   - Logs failure message on error

2. **Retry Logic:**
   - Retries on StandardError
   - Uses exponential backoff
   - Marks as failed after max retries

### Integration Tests

**Test File**: `spec/requests/quiver_data_integration_spec.rb`

**Test Case:**
```ruby
it 'fetches and stores congressional trades end-to-end', :vcr do
  # Start with empty database
  expect(QuiverTrade.count).to eq(0)
  
  # Run job
  FetchQuiverDataJob.perform_now(
    start_date: 30.days.ago.to_date,
    end_date: Date.today
  )
  
  # Verify trades saved
  expect(QuiverTrade.count).to be > 0
  
  # Verify data integrity
  trade = QuiverTrade.first
  expect(trade.ticker).to be_present
  expect(trade.trader_name).to be_present
  expect(trade.transaction_date).to be_present
  expect(trade.transaction_type).to be_in(['Purchase', 'Sale'])
end
```

### Manual Testing Checklist

```ruby
# 1. Test command directly in Rails console
result = FetchQuiverData.call(start_date: 30.days.ago.to_date)
puts "Fetched: #{result.new_trades_count} new trades"

# 2. Verify data in database
QuiverTrade.order(created_at: :desc).limit(10).pluck(:ticker, :trader_name, :transaction_date)

# 3. Test job
FetchQuiverDataJob.perform_now

# 4. Test idempotency (run again)
FetchQuiverDataJob.perform_now
# Should show 0 new trades, but same total

# 5. Test with specific ticker
FetchQuiverDataJob.perform_now(ticker: 'AAPL')

# 6. Verify logging
tail -f log/development.log | grep FetchQuiverData
```

---

## Implementation Plan

### Phase 1: Build FetchQuiverData Command (2-3 hours)

**Tasks:**
1. Create command file: `packs/data_fetching/app/commands/fetch_quiver_data.rb`
2. Implement core logic (fetch, process, save)
3. Add error handling and logging
4. Write unit tests
5. Test manually in Rails console

**Validation:**
- All unit tests pass
- Manual console test fetches and saves trades
- Logs are clear and informative

### Phase 2: Build FetchQuiverDataJob (1 hour)

**Tasks:**
1. Create job file: `packs/data_fetching/app/jobs/fetch_quiver_data_job.rb`
2. Implement job wrapper with retry logic
3. Add structured logging
4. Write job specs
5. Test manually

**Validation:**
- Job spec passes
- Manual job execution works
- Retry logic tested with simulated failure

### Phase 3: Integration & Documentation (1-2 hours)

**Tasks:**
1. Write integration test
2. Update `packs/data_fetching/README.md`
3. Update `packs/trading_strategies/README.md` with complete workflow
4. Create rake task for easy manual execution
5. Document in main README.md

**Rake Task:**
```ruby
# lib/tasks/quiver.rake
namespace :quiver do
  desc "Fetch congressional trading data from Quiver API"
  task fetch: :environment do
    start_date = ENV['START_DATE'] ? Date.parse(ENV['START_DATE']) : 60.days.ago.to_date
    end_date = ENV['END_DATE'] ? Date.parse(ENV['END_DATE']) : Date.today
    ticker = ENV['TICKER']
    
    puts "Fetching Quiver data..."
    puts "  Start date: #{start_date}"
    puts "  End date: #{end_date}"
    puts "  Ticker: #{ticker || 'all'}"
    
    FetchQuiverDataJob.perform_now(
      start_date: start_date,
      end_date: end_date,
      ticker: ticker
    )
  end
end

# Usage:
# rake quiver:fetch
# rake quiver:fetch START_DATE=2025-01-01
# rake quiver:fetch TICKER=AAPL
```

### Phase 4: End-to-End Validation (1 hour)

**Tasks:**
1. Clear QuiverTrade table
2. Run FetchQuiverDataJob
3. Verify data populated
4. Run ExecuteSimpleStrategyJob
5. Verify trades generated from fresh data
6. Check Alpaca paper account for orders

**Success Checklist:**
- [ ] QuiverTrade table has recent congressional trades
- [ ] GenerateTargetPortfolio uses this data
- [ ] ExecuteSimpleStrategyJob completes successfully
- [ ] Orders appear in Alpaca paper account
- [ ] All logs are clear and actionable

---

## Deployment Strategy

### Development Environment
1. Run FetchQuiverDataJob manually once to populate database
2. Test ExecuteSimpleStrategyJob uses that data
3. Verify end-to-end flow works

### Paper Trading (Immediate)
1. Set up manual daily execution:
   ```bash
   # Morning: Fetch data
   rails runner "FetchQuiverDataJob.perform_now"
   
   # After market open: Execute strategy
   rails runner "ExecuteSimpleStrategyJob.perform_now"
   ```

2. Monitor logs for issues
3. Iterate on any problems found

### Automated Scheduling (Week 2)

**Option A: Using whenever gem**
```ruby
# config/schedule.rb
every :day, at: '8:00am' do
  runner "FetchQuiverDataJob.perform_later"
end

every :day, at: '9:45am' do
  runner "ExecuteSimpleStrategyJob.perform_later"
end
```

**Option B: Using SolidQueue recurring jobs**
```ruby
# config/initializers/recurring_jobs.rb
SolidQueue.on_start do
  SolidQueue.recurring_jobs.add(
    FetchQuiverDataJob,
    cron: "0 8 * * 1-5",  # Weekdays 8 AM
    timezone: "America/New_York"
  )
  
  SolidQueue.recurring_jobs.add(
    ExecuteSimpleStrategyJob,
    cron: "45 9 * * 1-5",  # Weekdays 9:45 AM
    timezone: "America/New_York"
  )
end
```

### Production Deployment
1. Deploy code to production
2. Run manual data population once
3. Enable scheduled jobs
4. Set up monitoring/alerting
5. Monitor for 1 week before live trading

---

## Monitoring & Alerting

### Key Metrics to Track

1. **Data Freshness**: Last successful fetch timestamp
2. **Fetch Success Rate**: Percentage of successful fetches
3. **Data Volume**: Number of trades fetched per day
4. **Error Rate**: Percentage of trades that failed to save
5. **Job Duration**: Time taken to fetch and save data

### Logging Strategy

**Successful Run:**
```
FetchQuiverDataJob: Starting data fetch
FetchQuiverData: Fetching congressional trades...
FetchQuiverData: Received 150 trades from API
FetchQuiverData: Processed 150 trades - 12 new, 3 updated, 0 errors
FetchQuiverDataJob: SUCCESS - Fetched 150 trades (12 new, 3 updated)
FetchQuiverDataJob: Complete
```

**Failed Run:**
```
FetchQuiverDataJob: Starting data fetch
FetchQuiverData: API fetch failed: Connection timeout
FetchQuiverDataJob: FAILED - Failed to fetch data from Quiver API: Connection timeout
[Retry attempt 1/3]
```

### Alerting Rules

1. **Critical**: FetchQuiverDataJob fails after all retries
2. **Warning**: Error rate > 10% for individual trades
3. **Warning**: No new trades fetched in 7 days
4. **Info**: Job completes successfully

### Dashboard Queries

```ruby
# Recent job runs
FetchQuiverDataJob.last(10)

# Data freshness check
QuiverTrade.maximum(:created_at)

# Daily trade count
QuiverTrade.where(created_at: 24.hours.ago..Time.current).count

# Most active traders
QuiverTrade.group(:trader_name).count.sort_by { |_, v| -v }.first(10)
```

---

## Risk Analysis

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| QuiverQuant API rate limits | Medium | High | Implement exponential backoff, respect rate limits |
| API authentication failure | Low | High | Validate credentials in test suite, alert on failure |
| Database deadlocks | Low | Medium | Use transactions, implement retry logic |
| Large data volumes slow query | Low | Medium | Add database indexes if needed |
| Duplicate data corruption | Low | High | Use find_or_initialize_by with composite key |

### Operational Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Job doesn't run on schedule | Medium | High | Monitoring + alerting, manual backup process |
| Stale data not noticed | Medium | Medium | Add data freshness check to ExecuteSimpleStrategyJob |
| Failed job not investigated | Medium | Medium | Clear logging, alerting to Slack/email |
| Costs from excessive API calls | Low | Medium | Log API call count, set reasonable fetch window |

---

## Success Metrics

**Immediate (Today):**
- [ ] FetchQuiverData command implemented and tested
- [ ] FetchQuiverDataJob implemented and tested
- [ ] Manual execution successfully populates database
- [ ] All tests passing

**Short-term (This Week):**
- [ ] Daily manual execution working reliably
- [ ] ExecuteSimpleStrategyJob uses fresh data
- [ ] Paper trading generates orders successfully
- [ ] No data quality issues observed

**Long-term (Month 1):**
- [ ] Automated scheduling in production
- [ ] 99%+ job success rate
- [ ] Data freshness < 24 hours at all times
- [ ] Zero manual interventions needed

---

## Open Questions

1. **Data retention**: How long should we keep old QuiverTrade records?
   - **Recommendation**: Keep all historical data (disk is cheap, useful for backtesting)

2. **Backfill strategy**: Should we fetch historical data beyond 60 days initially?
   - **Recommendation**: Yes, fetch 1 year on first run for robust backtesting

3. **Multiple data sources**: Will we add more signal sources beyond Quiver?
   - **Recommendation**: Design FetchQuiverData to be template for future FetchXData commands

4. **API cost**: What's the cost per API call to QuiverQuant?
   - **Action**: Verify with QuiverQuant pricing, optimize fetch frequency if needed

5. **Data validation**: Should we validate trade data quality?
   - **Recommendation**: Add optional validation step (e.g., check for suspicious patterns)

---

## Appendix: Example Logs

### Successful First Run (Initial Population)
```
[2025-11-04 08:00:00] FetchQuiverDataJob: Starting data fetch
[2025-11-04 08:00:00]   start_date: 2024-09-05
[2025-11-04 08:00:00]   end_date: 2025-11-04
[2025-11-04 08:00:00]   ticker: all
[2025-11-04 08:00:01] Fetching congressional trades from Quiver API with params: {:start_date=>"2024-09-05", :end_date=>"2025-11-04", :limit=>100}
[2025-11-04 08:00:03] FetchQuiverData: Received 427 trades from API
[2025-11-04 08:00:15] FetchQuiverData: Processed 427 trades - 427 new, 0 updated, 0 errors
[2025-11-04 08:00:15] FetchQuiverDataJob: SUCCESS - Fetched 427 trades (427 new, 0 updated)
[2025-11-04 08:00:15] FetchQuiverDataJob: Complete
```

### Successful Incremental Run (Next Day)
```
[2025-11-05 08:00:00] FetchQuiverDataJob: Starting data fetch
[2025-11-05 08:00:01] FetchQuiverData: Received 156 trades from API
[2025-11-05 08:00:03] FetchQuiverData: Processed 156 trades - 8 new, 2 updated, 0 errors
[2025-11-05 08:00:03] FetchQuiverDataJob: SUCCESS - Fetched 156 trades (8 new, 2 updated)
```

### Failed Run with Retry
```
[2025-11-05 08:00:00] FetchQuiverDataJob: Starting data fetch
[2025-11-05 08:00:30] FetchQuiverData: API fetch failed: Execution expired
[2025-11-05 08:00:30] FetchQuiverDataJob: FAILED - Failed to fetch data from Quiver API: Execution expired
[2025-11-05 08:00:31] Retrying FetchQuiverDataJob (attempt 1/3, waiting 1s)...
[2025-11-05 08:00:32] FetchQuiverDataJob: Starting data fetch
[2025-11-05 08:00:35] FetchQuiverData: Received 156 trades from API
[2025-11-05 08:00:37] FetchQuiverDataJob: SUCCESS - Fetched 156 trades (8 new, 0 updated)
```

---

## Approval Checklist

Before implementation begins:
- [ ] Technical design reviewed and approved
- [ ] Test strategy validated
- [ ] Timeline is realistic
- [ ] Risks identified and mitigated
- [ ] Success criteria agreed upon
- [ ] QuiverQuant API credentials available

---

## Next Steps

1. **Review this proposal** with stakeholders
2. **Get API credentials** from QuiverQuant if not already available
3. **Create feature branch**: `feature/fetch-quiver-data`
4. **Start implementation**: Phase 1 (FetchQuiverData command)
5. **Iterate**: Test, refine, deploy

**Target completion**: End of day 2025-11-04

**Blocker removal**: This unblocks paper trading, which is critical path to live trading

