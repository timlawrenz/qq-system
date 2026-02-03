# audit-trail Specification

## Purpose
TBD - created by archiving change trade-outbox-pattern. Update Purpose after archive.
## Requirements
### Requirement: Data Ingestion Audit Logging
The system SHALL log all data fetching operations (cron jobs) to enable regulatory compliance and debugging.

#### Scenario: Log congressional data fetch
- **GIVEN** the cron job `data_fetch:congress_daily` is scheduled to run
- **WHEN** the rake task executes at 7:00 AM
- **THEN** a DataIngestionRun record is created with status "running"
- **AND** the task name is "data_fetch:congress_daily"
- **AND** the data source is "quiverquant_congress"
- **AND** the started_at timestamp is recorded

#### Scenario: Track fetched records
- **GIVEN** a DataIngestionRun is in progress
- **WHEN** QuiverTrade records are created or updated
- **THEN** DataIngestionRunRecord junction records link each QuiverTrade to the run
- **AND** the operation type ("created", "updated", "skipped") is recorded
- **AND** the run's records_created and records_updated counts are incremented

#### Scenario: Log API calls during ingestion
- **GIVEN** a DataIngestionRun is fetching data from QuiverQuant API
- **WHEN** an API request is made to `/api/v1/congress`
- **THEN** an ApiRequest payload is stored with endpoint, method, and parameters
- **AND** the ApiResponse payload is stored with status code and response body
- **AND** an ApiCallLog links the request/response pair to the DataIngestionRun

#### Scenario: Handle ingestion failure
- **GIVEN** a DataIngestionRun is in progress
- **WHEN** the QuiverQuant API returns a 500 error
- **THEN** the DataIngestionRun status is updated to "failed"
- **AND** the error message is stored
- **AND** the failed_at timestamp is recorded
- **AND** no partial data is persisted

#### Scenario: Query ingestion history
- **GIVEN** multiple DataIngestionRuns have completed
- **WHEN** querying for runs in the last 24 hours
- **THEN** all runs are returned ordered by started_at DESC
- **AND** each run includes counts of records fetched, created, updated
- **AND** the query completes in less than 50ms

---

### Requirement: Centralized API Payload Storage
The system SHALL store all API request/response payloads in a centralized table using Single Table Inheritance (STI).

#### Scenario: Store Alpaca API request
- **GIVEN** a trade is being executed via Alpaca API
- **WHEN** the order request is built
- **THEN** an ApiRequest record is created with type "AuditTrail::ApiRequest"
- **AND** the payload includes endpoint "/v2/orders", method "POST", and order parameters
- **AND** the source is "alpaca"
- **AND** the captured_at timestamp is recorded

#### Scenario: Store Alpaca API response
- **GIVEN** an Alpaca API request has been sent
- **WHEN** the API returns a response
- **THEN** an ApiResponse record is created with type "AuditTrail::ApiResponse"
- **AND** the payload includes status, order_id, filled_qty, and filled_avg_price
- **AND** the source is "alpaca"
- **AND** the captured_at timestamp is recorded

#### Scenario: Reference API payloads from execution
- **GIVEN** an ApiRequest and ApiResponse exist for a trade execution
- **WHEN** a TradeExecution record is created
- **THEN** it references the ApiRequest via api_request_payload_id FK
- **AND** it references the ApiResponse via api_response_payload_id FK
- **AND** no JSONB columns duplicate the payload data

#### Scenario: Query failed API calls
- **GIVEN** multiple API responses exist from the last 24 hours
- **WHEN** querying for failed responses (status code >= 400)
- **THEN** all failed ApiResponse records are returned
- **AND** they can be grouped by source ("alpaca", "quiverquant")
- **AND** the error messages are accessible via payload JSONB

#### Scenario: Purge old API payloads
- **GIVEN** API payloads older than 2 years exist
- **WHEN** the retention policy rake task runs
- **THEN** all ApiPayload records with captured_at < 2 years ago are deleted
- **AND** TradeExecution and ApiCallLog records remain (audit trail intact)
- **AND** the deletion completes in less than 1 second per 1000 records

---

### Requirement: Trade Decision Outbox Pattern
The system SHALL capture trade intent BEFORE execution using the outbox pattern with hybrid normalization (FK + JSONB).

#### Scenario: Create trade decision from strategy signal
- **GIVEN** the CongressionalTradingStrategy generates a BUY signal for AAPL
- **WHEN** the CreateTradeDecision command is called
- **THEN** a TradeDecision record is created with status "pending"
- **AND** the decision_id is a unique UUID
- **AND** the symbol, side, quantity, and order_type are stored
- **AND** the primary_quiver_trade_id FK links to the source QuiverTrade
- **AND** the primary_ingestion_run_id FK links to the DataIngestionRun that fetched the data
- **AND** the decision_rationale JSONB includes signal_strength, confidence_score, and trigger_event

#### Scenario: Link decision to data lineage
- **GIVEN** a TradeDecision is being created
- **WHEN** recent DataIngestionRuns exist (completed in last 24 hours)
- **THEN** the decision_rationale includes a data_lineage object
- **AND** the data_lineage lists up to 5 recent ingestion runs with run_id, task_name, and completed_at
- **AND** the primary_ingestion_run_id is set to the most recent run

#### Scenario: Store market and portfolio context
- **GIVEN** a TradeDecision is being created for AAPL
- **WHEN** market data is available
- **THEN** the decision_rationale includes market_context with current_price and volume
- **AND** the decision_rationale includes portfolio_context with buying_power and portfolio_value
- **AND** all context is captured at decision time (before execution)

#### Scenario: Query decisions by signal strength
- **GIVEN** multiple TradeDecisions exist with varying signal strengths
- **WHEN** querying decisions ordered by signal_strength DESC
- **THEN** decisions are returned sorted by (decision_rationale->>'signal_strength')::numeric
- **AND** the query uses the GIN index on decision_rationale
- **AND** the query completes in less than 100ms for 10,000 records

#### Scenario: Find decisions from specific QuiverTrade
- **GIVEN** a QuiverTrade record with ID 12345 triggered multiple trade decisions
- **WHEN** querying TradeDecision.where(primary_quiver_trade_id: 12345)
- **THEN** all decisions linked to that QuiverTrade are returned
- **AND** the FK constraint ensures referential integrity
- **AND** the query completes in less than 10ms

---

### Requirement: Synchronous Trade Execution Logging
The system SHALL execute trades synchronously (no queuing) and log all API interactions with normalized FK references.

#### Scenario: Execute pending trade decision
- **GIVEN** a TradeDecision with status "pending" exists
- **WHEN** the ExecuteTradeDecision command is called
- **THEN** an ApiRequest is created and stored before the API call
- **AND** the Alpaca API is called synchronously (no background job)
- **AND** an ApiResponse is created and stored after the API call
- **AND** a TradeExecution record is created linking both payloads
- **AND** the TradeDecision status is updated to "executed" or "failed"

#### Scenario: Handle successful execution
- **GIVEN** a trade decision for AAPL 100 shares is being executed
- **WHEN** the Alpaca API returns status "filled" with filled_qty 100
- **THEN** the TradeExecution status is "filled"
- **AND** the filled_quantity is 100
- **AND** the filled_avg_price is extracted from the response
- **AND** the alpaca_order_id is stored
- **AND** the TradeDecision status is updated to "executed"
- **AND** the executed_at timestamp is recorded

#### Scenario: Handle execution failure
- **GIVEN** a trade decision is being executed
- **WHEN** the Alpaca API returns 403 "insufficient buying power"
- **THEN** the TradeExecution status is "rejected"
- **AND** the error_message is "insufficient buying power"
- **AND** the http_status_code is 403
- **AND** the TradeDecision status is updated to "failed"
- **AND** the failed_at timestamp is recorded
- **AND** NO retry is attempted (preserves signal ordering)

#### Scenario: Extract key fields for querying
- **GIVEN** a TradeExecution references ApiRequest and ApiResponse payloads
- **WHEN** querying for executions by status or alpaca_order_id
- **THEN** the extracted fields (status, alpaca_order_id, http_status_code) enable fast queries
- **AND** no JOINs to api_payloads table are required for filtering
- **AND** queries complete in less than 20ms

#### Scenario: Preserve signal strength ordering
- **GIVEN** the CongressionalTradingStrategy generates 5 signals with strengths [9, 7, 8, 6, 10]
- **WHEN** signals are sorted by strength DESC before execution
- **THEN** decisions are created in order: 10, 9, 8, 7, 6
- **AND** executions happen synchronously in the same order
- **AND** if signal strength 9 fails with insufficient funds, execution continues with 8
- **AND** no retry logic disrupts the ordering

---

### Requirement: Symbol Activity Reporting
The system SHALL support queries for complete activity history of a symbol across data ingestion, decisions, and executions.

#### Scenario: Query all AAPL activity in 2025
- **GIVEN** multiple AAPL-related records exist across the year 2025
- **WHEN** SymbolActivityReport.generate(symbol: "AAPL", start_date: "2025-01-01", end_date: "2025-12-31") is called
- **THEN** the report includes data_ingested (QuiverTrades with ingestion timestamps)
- **AND** the report includes decisions_made (all TradeDecisions with rationale)
- **AND** the report includes trades_executed (all successful TradeExecutions)
- **AND** the report includes summary statistics (success rate, failure breakdown)
- **AND** the query completes in less than 200ms

#### Scenario: Trace decision back to source data
- **GIVEN** a TradeDecision for AAPL created at 9:30 AM on Dec 24, 2025
- **WHEN** querying the decision's data lineage
- **THEN** the primary_quiver_trade_id links to the source QuiverTrade
- **AND** the primary_ingestion_run_id links to the DataIngestionRun at 7:05 AM
- **AND** the DataIngestionRunRecord confirms the QuiverTrade was ingested in that run
- **AND** the complete chain is: DataIngestionRun → QuiverTrade → TradeDecision → TradeExecution

#### Scenario: Analyze failed trades by reason
- **GIVEN** multiple TradeDecisions with status "failed" exist
- **WHEN** querying failed decisions grouped by failure reason
- **THEN** failures are grouped by error_message ("insufficient buying power", "market closed", etc.)
- **AND** counts per reason are returned
- **AND** the query identifies patterns (e.g., always fails on Mondays)

#### Scenario: Strategy success rate independent of execution
- **GIVEN** a strategy generates 100 signals (TradeDecisions)
- **WHEN** 80 execute successfully and 20 fail due to insufficient buying power
- **THEN** the success rate is calculated as 80% (executed / total)
- **AND** this is distinct from win rate (profitable vs unprofitable)
- **AND** the query separates signal quality from execution issues

---

### Requirement: Regulatory Compliance and Audit Trail
The system SHALL provide a complete audit trail for regulatory compliance (SEC Rule 15c3-5).

#### Scenario: Prove data availability at decision time
- **GIVEN** a regulator asks "What AAPL data did you have on Dec 24, 2025 at 9:30 AM?"
- **WHEN** querying DataIngestionRuns completed before 9:30 AM that day
- **THEN** all runs with data_source "quiverquant_congress" are returned
- **AND** the ingested_record_ids show which QuiverTrades were available
- **AND** this proves no advance knowledge of trades filed later that day

#### Scenario: Reconstruct decision rationale
- **GIVEN** a TradeDecision created 6 months ago
- **WHEN** querying the decision's rationale
- **THEN** the decision_rationale JSONB contains all original context
- **AND** the primary_quiver_trade_id FK still references the source data
- **AND** the data_lineage shows which ingestion runs provided the data
- **AND** the decision can be fully reconstructed without any data loss

#### Scenario: Full audit trail for single trade
- **GIVEN** a trade for AAPL executed on Dec 24, 2025
- **WHEN** generating a full audit trail report
- **THEN** the report includes:
  - DataIngestionRun: when congressional data was fetched (7:05 AM)
  - QuiverTrade: the specific congressional trade (Nancy Pelosi purchase)
  - TradeDecision: when and why the decision was made (9:30 AM)
  - TradeExecution: the API request/response (9:31 AM)
  - AlpacaOrder: the final fill details
- **AND** all timestamps prove chronological order
- **AND** all FK constraints ensure data integrity

#### Scenario: Retention policy preserves audit trail
- **GIVEN** API payloads older than 2 years are purged
- **WHEN** querying a 3-year-old trade
- **THEN** the TradeDecision, TradeExecution, and AlpacaOrder records still exist
- **AND** the decision rationale and execution status are intact
- **AND** only the raw API request/response JSONB is missing
- **AND** this is acceptable for long-term compliance (2-year retention is typical)

---

