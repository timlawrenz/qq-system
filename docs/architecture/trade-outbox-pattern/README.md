# Trade Outbox Pattern - Technical Architecture

> **OpenSpec Change Proposal**: See `/openspec/changes/trade-outbox-pattern/`

This directory contains detailed technical specifications for the Trade Outbox Pattern implementation.

## Overview

The Trade Outbox Pattern introduces comprehensive auditability and traceability to the trading system through:
1. **Data Ingestion Logging** - Track all rake task executions
2. **API Payload Storage** - Centralized storage using STI pattern
3. **Trade Decision Outbox** - Capture intent before execution
4. **Trade Execution Logging** - Synchronous execution with full API tracking
5. **Symbol Activity Reporting** - Query complete audit chain

## Architecture Documents

### [data-ingestion-logging.md](./data-ingestion-logging.md)
**Phase 1 - Week 1**

Tracks all data fetching operations (cron jobs):
- **Models**: `DataIngestionRun`, `DataIngestionRunRecord` (junction), `ApiCallLog`
- **Command**: `LogDataIngestion` (GLCommand wrapper)
- **Benefits**: Prove when data became available, debug failed ingestions, data quality monitoring

**Key Features:**
- Fully normalized (junction table instead of JSONB array)
- Polymorphic association for ingested records
- Links to API payloads for complete request/response history

### [api-payload-storage.md](./api-payload-storage.md)
**Phase 2 - Week 1-2**

Centralized storage for all API request/response pairs:
- **Models**: `ApiPayload` (STI base), `ApiRequest`, `ApiResponse`
- **Pattern**: Single Table Inheritance (STI)
- **Benefits**: Reusable across data ingestion and trading, centralized retention policy

**Key Features:**
- STI discriminator column for type-specific behavior
- Referenced via FK from `TradeExecution` and `ApiCallLog`
- Zero JSONB duplication (normalized)
- Helper methods for common fields (status_code, success?, error?)

### [trade-decision-model.md](./trade-decision-model.md)
**Phase 3 - Week 2**

Implements outbox pattern for trade decisions:
- **Model**: `TradeDecision`
- **Command**: `CreateTradeDecision`
- **State Machine**: pending → executed/failed/cancelled

**Key Features:**
- **Hybrid normalization**: FK for primary signals + JSONB for flexible context
- `primary_quiver_trade_id` - FK to main signal source
- `primary_ingestion_run_id` - FK to prove data availability
- `decision_rationale` - JSONB for strategy-specific context
- **No retry logic** - preserves signal strength ordering

### [trade-execution-model.md](./trade-execution-model.md)
**Phase 4 - Week 2**

Logs actual trade executions:
- **Model**: `TradeExecution`
- **Command**: `ExecuteTradeDecision`
- **Execution**: Synchronous (no queuing, no retries)

**Key Features:**
- References `api_request_payload_id` and `api_response_payload_id` (FK)
- Extracts common fields for fast querying (status, price, quantity)
- Updates `TradeDecision` status based on execution result
- Handles errors gracefully (logs failure reason, no retry)

## Database Schema Summary

```
api_payloads (STI)
├── id
├── type (STI discriminator: ApiRequest, ApiResponse)
├── payload (JSONB)
├── source ('alpaca', 'quiverquant', 'propublica')
└── captured_at

data_ingestion_runs
├── id
├── run_id (UUID)
├── task_name
├── status (running → completed/failed)
├── records_fetched, records_created, records_updated
└── started_at, completed_at, failed_at

data_ingestion_run_records (junction)
├── id
├── data_ingestion_run_id (FK)
├── record_type (polymorphic: 'QuiverTrade', 'PoliticianProfile')
├── record_id (polymorphic)
└── operation ('created', 'updated', 'skipped')

api_call_logs
├── id
├── data_ingestion_run_id (FK)
├── api_request_payload_id (FK → api_payloads)
├── api_response_payload_id (FK → api_payloads)
├── endpoint, http_status_code, duration_ms
└── created_at

trade_decisions
├── id
├── decision_id (UUID)
├── strategy_name, strategy_version
├── symbol, side, quantity
├── primary_quiver_trade_id (FK → quiver_trades)
├── primary_ingestion_run_id (FK → data_ingestion_runs)
├── decision_rationale (JSONB - hybrid approach)
├── status (pending → executed/failed/cancelled)
└── created_at, executed_at, failed_at

trade_executions
├── id
├── trade_decision_id (FK)
├── execution_id (UUID)
├── api_request_payload_id (FK → api_payloads)
├── api_response_payload_id (FK → api_payloads)
├── status, alpaca_order_id, http_status_code
├── filled_quantity, filled_avg_price, commission
└── submitted_at, filled_at, rejected_at
```

## Complete Audit Chain

```
7:00 AM: Cron job executes
  └─> DataIngestionRun created (status: "running")
      └─> QuiverQuant API call
          ├─> ApiRequest stored (endpoint, params)
          └─> ApiResponse stored (status, data)
              └─> ApiCallLog links payloads to run
                  └─> QuiverTrade records created
                      └─> DataIngestionRunRecord junction (operation: "created")
                          └─> DataIngestionRun status: "completed"

9:30 AM: Strategy executes
  └─> TradeDecision created (status: "pending")
      ├─> primary_quiver_trade_id → QuiverTrade (FK)
      ├─> primary_ingestion_run_id → DataIngestionRun (FK)
      └─> decision_rationale includes data_lineage
          └─> ExecuteTradeDecision command (synchronous)
              ├─> ApiRequest stored (Alpaca order params)
              └─> Alpaca API call
                  └─> ApiResponse stored (fill details)
                      └─> TradeExecution created
                          ├─> api_request_payload_id (FK)
                          ├─> api_response_payload_id (FK)
                          └─> extracted fields (status, price, qty)
                              └─> TradeDecision status: "executed"
```

## Query Examples

### "Show me all AAPL activity in 2025"
```ruby
report = SymbolActivityReport.generate(
  symbol: "AAPL",
  start_date: Date.new(2025, 1, 1),
  end_date: Date.new(2025, 12, 31)
)

# Returns:
# - data_ingested: QuiverTrades with ingestion timestamps
# - decisions_made: All TradeDecisions with rationale
# - trades_executed: Successful TradeExecutions
# - summary: Success rate, failure breakdown

# Performance: <200ms for full year
```

### "What data did we have when we made this trade?"
```ruby
decision = TradeDecision.find_by(decision_id: "uuid-123")

# Primary signal
quiver_trade = decision.primary_quiver_trade
# => QuiverTrade: Nancy Pelosi purchased AAPL on 2025-12-20

# When data became available
ingestion_run = decision.primary_ingestion_run
# => DataIngestionRun completed at 2025-12-24 07:05:30

# All data available at decision time
decision.decision_rationale['data_lineage']['ingestion_runs']
# => Array of recent runs with timestamps
```

### "Why did this trade fail?"
```ruby
execution = TradeExecution.find_by(alpaca_order_id: "order-123")

execution.status
# => "rejected"

execution.error_message
# => "insufficient buying power"

execution.http_status_code
# => 403

# Full API context
execution.api_response_payload.payload
# => { "code": 40310000, "message": "insufficient buying power", ... }
```

## Pack Structure

```
packs/audit_trail/
├── app/
│   ├── models/
│   │   └── audit_trail/
│   │       ├── data_ingestion_run.rb
│   │       ├── data_ingestion_run_record.rb
│   │       ├── api_payload.rb (STI base)
│   │       ├── api_request.rb (STI subclass)
│   │       ├── api_response.rb (STI subclass)
│   │       ├── api_call_log.rb
│   │       ├── trade_decision.rb
│   │       └── trade_execution.rb
│   ├── commands/
│   │   └── audit_trail/
│   │       ├── log_data_ingestion.rb
│   │       ├── create_trade_decision.rb
│   │       └── execute_trade_decision.rb
│   └── queries/
│       └── audit_trail/
│           ├── symbol_activity_report.rb
│           ├── strategy_performance_report.rb
│           └── failure_analysis_report.rb
├── spec/
│   ├── models/
│   ├── commands/
│   └── integration/
└── package.yml
```

## Implementation Tasks

See `/openspec/changes/trade-outbox-pattern/tasks.md` for detailed 89-task checklist across 6 phases.

**Total Duration**: 3-4 weeks  
**Storage**: ~26MB/year for aggressive trading  
**Performance**: <200ms for year-long symbol activity reports

## Success Metrics

✅ **Auditability**
- 100% of data ingestion runs logged with timestamps
- 100% of trade decisions captured before execution
- Can prove when data became available to system

✅ **Visibility**
- Clear separation of "signals generated" vs "trades executed"
- Failure rate by reason (buying power, API errors)
- Strategy success rate independent of execution issues

✅ **Compliance**
- SEC Rule 15c3-5 ready (audit trail for automated trading)
- Can answer: "What AAPL data did we have when we made this trade?"
- Can reconstruct decision rationale 6 months later

✅ **Performance**
- Data ingestion logging: <50ms overhead per rake task
- Decision creation: <100ms
- Execution logging: <20ms overhead
- Symbol activity query: <200ms for full year
