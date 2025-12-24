# Implementation Tasks: Trade Outbox Pattern

**Change ID**: `trade-outbox-pattern`  
**Total Phases**: 6  
**Total Tasks**: 89  
**Estimated Duration**: 3-4 weeks

---

## Phase 1: Data Ingestion Logging (Week 1)

**Goal**: Quick win - log all data fetching operations  
**Tasks**: 15 | **Completed**: 0/15

### Database Migrations

- [ ] **Task 1.1**: Create `data_ingestion_runs` table migration
  - Run: `rails g migration CreateDataIngestionRuns`
  - Follow spec: `specs/data-ingestion-logging.md`
  - Include indexes for (task_name, started_at), (data_source, started_at)

- [ ] **Task 1.2**: Create `data_ingestion_run_records` table migration (junction)
  - Run: `rails g migration CreateDataIngestionRunRecords`
  - Polymorphic association: record_type, record_id
  - Composite unique index

- [ ] **Task 1.3**: Create `api_call_logs` table migration
  - Run: `rails g migration CreateApiCallLogs`
  - FK to data_ingestion_runs
  - FK to api_payloads (will be created in Phase 2)

- [ ] **Task 1.4**: Run migrations
  - `bundle exec rails db:migrate`
  - Verify schema.rb updated

### Models

- [ ] **Task 1.5**: Create `AuditTrail::DataIngestionRun` model
  - Location: `packs/audit_trail/app/models/audit_trail/data_ingestion_run.rb`
  - Include AASM gem for state machine
  - Add scopes: recent, for_task, for_source, successful, failed_runs

- [ ] **Task 1.6**: Create `AuditTrail::DataIngestionRunRecord` model
  - Location: `packs/audit_trail/app/models/audit_trail/data_ingestion_run_record.rb`
  - Polymorphic belongs_to :record
  - Scopes for operation types

- [ ] **Task 1.7**: Create `AuditTrail::ApiCallLog` model
  - Location: `packs/audit_trail/app/models/audit_trail/api_call_log.rb`
  - FK to data_ingestion_run, api payloads

### GLCommand

- [ ] **Task 1.8**: Create `AuditTrail::LogDataIngestion` command
  - Location: `packs/audit_trail/app/commands/audit_trail/log_data_ingestion.rb`
  - Wrap block execution with audit logging
  - Handle success/failure cases
  - Create junction records

### Rake Task Updates

- [ ] **Task 1.9**: Update `data_fetch:congress_daily` rake task
  - Wrap with LogDataIngestion command
  - Return hash with expected keys (fetched, created, updated, skipped)

- [ ] **Task 1.10**: Update `data_fetch:insider_daily` rake task
  - Same pattern as congress_daily

- [ ] **Task 1.11**: Update `maintenance:daily` rake task (if applicable)
  - Same pattern

### Testing

- [ ] **Task 1.12**: Unit tests for DataIngestionRun model
  - Location: `spec/packs/audit_trail/models/data_ingestion_run_spec.rb`
  - Test state machine transitions

- [ ] **Task 1.13**: Unit tests for LogDataIngestion command
  - Location: `spec/packs/audit_trail/commands/log_data_ingestion_spec.rb`
  - Test success and failure scenarios

- [ ] **Task 1.14**: Integration test for complete ingestion flow
  - Location: `spec/packs/audit_trail/integration/data_ingestion_logging_spec.rb`
  - Test rake task → logging → junction records

- [ ] **Task 1.15**: Manual validation
  - Run: `bundle exec rake data_fetch:congress_daily`
  - Verify DataIngestionRun created
  - Verify DataIngestionRunRecords created
  - Check logs for success message

---

## Phase 2: API Payload Storage (STI) (Week 1-2)

**Goal**: Centralized API payload storage  
**Tasks**: 12 | **Completed**: 0/12

### Database Migration

- [ ] **Task 2.1**: Create `api_payloads` table migration (STI)
  - Run: `rails g migration CreateApiPayloads`
  - Follow spec: `specs/api-payload-storage.md`
  - Include GIN index for payload JSONB column

- [ ] **Task 2.2**: Run migration
  - `bundle exec rails db:migrate`

### Models

- [ ] **Task 2.3**: Create `AuditTrail::ApiPayload` base model
  - Location: `packs/audit_trail/app/models/audit_trail/api_payload.rb`
  - STI base class
  - Scopes: recent, for_source, older_than

- [ ] **Task 2.4**: Create `AuditTrail::ApiRequest` subclass
  - Location: `packs/audit_trail/app/models/audit_trail/api_request.rb`
  - Helper methods: endpoint, http_method, params

- [ ] **Task 2.5**: Create `AuditTrail::ApiResponse` subclass
  - Location: `packs/audit_trail/app/models/audit_trail/api_response.rb`
  - Helper methods: status_code, success?, error?

### Update Phase 1 Models

- [ ] **Task 2.6**: Update `ApiCallLog` to reference `api_payloads`
  - Update associations: belongs_to :api_request_payload, :api_response_payload

- [ ] **Task 2.7**: Update `LogDataIngestion` command to create ApiPayload records
  - Create ApiRequest and ApiResponse instead of storing in JSONB

### Testing

- [ ] **Task 2.8**: Unit tests for ApiPayload STI
  - Location: `spec/packs/audit_trail/models/api_payload_spec.rb`
  - Test STI type discrimination
  - Test helper methods

- [ ] **Task 2.9**: Unit tests for ApiRequest
  - Test payload_has_required_keys validation

- [ ] **Task 2.10**: Unit tests for ApiResponse
  - Test success? and error? methods

- [ ] **Task 2.11**: Integration test for API payload storage
  - Test creating request/response pairs
  - Test retrieval via FK

- [ ] **Task 2.12**: Manual validation
  - Run data ingestion task
  - Verify ApiPayload records created
  - Verify ApiCallLog references correct payloads

---

## Phase 3: Trade Decision Model (Week 2)

**Goal**: Implement outbox pattern for trade decisions  
**Tasks**: 18 | **Completed**: 0/18

### Database Migration

- [ ] **Task 3.1**: Create `trade_decisions` table migration
  - Run: `rails g migration CreateTradeDecisions`
  - Follow spec: `specs/trade-decision-model.md`
  - Include FK to quiver_trades (primary_quiver_trade_id)
  - Include FK to data_ingestion_runs (primary_ingestion_run_id)
  - Include GIN index for decision_rationale JSONB

- [ ] **Task 3.2**: Run migration
  - `bundle exec rails db:migrate`

### Models

- [ ] **Task 3.3**: Create `AuditTrail::TradeDecision` model
  - Location: `packs/audit_trail/app/models/audit_trail/trade_decision.rb`
  - Include AASM for state machine (pending → executed/failed/cancelled)
  - Associations: belongs_to primary_quiver_trade, primary_ingestion_run
  - Scopes: pending_decisions, executed_decisions, failed_decisions

- [ ] **Task 3.4**: Add associations to existing models
  - QuiverTrade: `has_many :trade_decisions`
  - DataIngestionRun: `has_many :trade_decisions`

### GLCommand

- [ ] **Task 3.5**: Create `AuditTrail::CreateTradeDecision` command
  - Location: `packs/audit_trail/app/commands/audit_trail/create_trade_decision.rb`
  - Auto-link data lineage (recent ingestion runs)
  - Generate UUID for decision_id

### Testing

- [ ] **Task 3.6**: Unit tests for TradeDecision model
  - Location: `spec/packs/audit_trail/models/trade_decision_spec.rb`
  - Test validations
  - Test state machine transitions
  - Test helper methods (signal_strength, confidence_score)

- [ ] **Task 3.7**: Unit tests for CreateTradeDecision command
  - Location: `spec/packs/audit_trail/commands/create_trade_decision_spec.rb`
  - Test decision creation with data lineage
  - Test FK linking to QuiverTrade and DataIngestionRun

### Strategy Integration (Temporary)

- [ ] **Task 3.8**: Create test strategy that uses CreateTradeDecision
  - Location: `spec/support/test_strategy.rb`
  - Verify decision creation before execution

- [ ] **Task 3.9**: Manual validation
  - Run test strategy
  - Verify TradeDecision records created
  - Verify FKs linked correctly
  - Check decision_rationale JSONB structure

### Factories

- [ ] **Task 3.10**: Create FactoryBot factory for TradeDecision
  - Location: `spec/factories/audit_trail/trade_decision.rb`

- [ ] **Task 3.11**: Create FactoryBot factory for DataIngestionRun
  - Location: `spec/factories/audit_trail/data_ingestion_run.rb`

- [ ] **Task 3.12**: Create FactoryBot factory for ApiRequest
  - Location: `spec/factories/audit_trail/api_request.rb`

- [ ] **Task 3.13**: Create FactoryBot factory for ApiResponse
  - Location: `spec/factories/audit_trail/api_response.rb`

### Package.yml

- [ ] **Task 3.14**: Create `packs/audit_trail/package.yml`
  - Define dependencies: data_fetching, trades, alpaca_api
  - Enforce boundaries with Packwerk

- [ ] **Task 3.15**: Run Packwerk validation
  - `bundle exec packwerk validate`
  - `bundle exec packwerk check`

### Documentation

- [ ] **Task 3.16**: Add README to audit_trail pack
  - Location: `packs/audit_trail/README.md`
  - Explain purpose, models, commands

- [ ] **Task 3.17**: Update CONVENTIONS.md if needed
  - Document audit trail pack conventions

- [ ] **Task 3.18**: Update main README.md
  - Add section on audit trail capabilities

---

## Phase 4: Trade Execution Model (Week 2)

**Goal**: Log actual trade executions with API calls  
**Tasks**: 15 | **Completed**: 0/15

### Database Migration

- [ ] **Task 4.1**: Create `trade_executions` table migration
  - Run: `rails g migration CreateTradeExecutions`
  - Follow spec: `specs/trade-execution-model.md`
  - FK to trade_decisions
  - FK to api_payloads (request and response)

- [ ] **Task 4.2**: Add trade_decision_id to alpaca_orders table
  - Run: `rails g migration AddTradeDecisionToAlpacaOrders`
  - Optional FK for backward compatibility

- [ ] **Task 4.3**: Run migrations
  - `bundle exec rails db:migrate`

### Models

- [ ] **Task 4.4**: Create `AuditTrail::TradeExecution` model
  - Location: `packs/audit_trail/app/models/audit_trail/trade_execution.rb`
  - Associations: belongs_to trade_decision, api_request_payload, api_response_payload
  - Scopes: successful, failed, pending

- [ ] **Task 4.5**: Update AlpacaOrder model
  - Add: `belongs_to :trade_decision, optional: true`

### GLCommand

- [ ] **Task 4.6**: Create `AuditTrail::ExecuteTradeDecision` command
  - Location: `packs/audit_trail/app/commands/audit_trail/execute_trade_decision.rb`
  - Synchronous execution (no queuing)
  - Store API request/response as ApiPayload
  - Create TradeExecution record
  - Update TradeDecision status

### Testing

- [ ] **Task 4.7**: Unit tests for TradeExecution model
  - Location: `spec/packs/audit_trail/models/trade_execution_spec.rb`
  - Test validations
  - Test helper methods (success?, failure?)

- [ ] **Task 4.8**: Unit tests for ExecuteTradeDecision command
  - Location: `spec/packs/audit_trail/commands/execute_trade_decision_spec.rb`
  - Test successful execution
  - Test failed execution (insufficient buying power)
  - Test error handling

- [ ] **Task 4.9**: Integration test for full flow
  - Location: `spec/packs/audit_trail/integration/trade_execution_flow_spec.rb`
  - Test: CreateTradeDecision → ExecuteTradeDecision → TradeExecution
  - Verify audit trail completeness

- [ ] **Task 4.10**: FactoryBot factory for TradeExecution
  - Location: `spec/factories/audit_trail/trade_execution.rb`

### Mock Alpaca API

- [ ] **Task 4.11**: Create test helpers for mocking Alpaca API
  - Location: `spec/support/alpaca_api_helpers.rb`
  - Mock successful responses
  - Mock failure responses (403, 422, 429)

### Manual Validation

- [ ] **Task 4.12**: Test in paper trading mode
  - Create decision → execute → verify execution record
  - Test with insufficient buying power (should fail gracefully)

- [ ] **Task 4.13**: Verify API payload storage
  - Check ApiRequest created before API call
  - Check ApiResponse created after API call
  - Verify TradeExecution links to both

- [ ] **Task 4.14**: Verify decision status updates
  - Successful execution → decision.status = 'executed'
  - Failed execution → decision.status = 'failed'

- [ ] **Task 4.15**: Run through complete flow
  - Data ingestion → Decision → Execution
  - Verify all FK links intact

---

## Phase 5: Strategy Integration (Week 2-3)

**Goal**: Update strategies to use new pattern  
**Tasks**: 16 | **Completed**: 0/16

### Update CongressionalTradingStrategy

- [ ] **Task 5.1**: Refactor to use GLCommand pattern
  - Location: `packs/trading_strategies/app/commands/trading_strategies/execute_congressional_strategy.rb`
  - Use CreateTradeDecision for each signal
  - Use ExecuteTradeDecision immediately after (synchronous)

- [ ] **Task 5.2**: Preserve signal ordering
  - Sort signals by strength before creating decisions
  - Execute in order (strongest first)

- [ ] **Task 5.3**: Handle execution failures gracefully
  - Log failure, continue to next signal
  - No retries

- [ ] **Task 5.4**: Update tests for CongressionalTradingStrategy
  - Test decision creation
  - Test execution ordering
  - Test failure handling

### Update Other Strategies (if any)

- [ ] **Task 5.5**: Identify all active trading strategies
  - List strategies in `packs/trading_strategies/`

- [ ] **Task 5.6**: Update each strategy to use new pattern
  - Same pattern as Task 5.1-5.3

### Backward Compatibility

- [ ] **Task 5.7**: Add feature flag for new pattern
  - ENV var: `USE_AUDIT_TRAIL=true`
  - Allow gradual rollout

- [ ] **Task 5.8**: Dual-write period (optional)
  - Keep creating AlpacaOrder records in addition to TradeExecution
  - For migration safety

### Integration Tests

- [ ] **Task 5.9**: End-to-end test: data ingestion → strategy → execution
  - Location: `spec/integration/full_trading_flow_spec.rb`
  - Mock cron job → strategy execution → verify audit trail

- [ ] **Task 5.10**: Test multiple signals in single strategy run
  - Verify ordering preserved
  - Verify all decisions created before any execution

- [ ] **Task 5.11**: Test failure scenarios
  - Insufficient buying power
  - API errors
  - Verify audit trail for failures

### Performance Testing

- [ ] **Task 5.12**: Benchmark decision creation
  - Target: <100ms per decision
  - Run with 100 decisions

- [ ] **Task 5.13**: Benchmark execution logging
  - Target: <20ms overhead per execution
  - Run with 100 executions

- [ ] **Task 5.14**: Database query performance
  - Test eager loading for API payloads
  - Ensure no N+1 queries

### Manual Validation

- [ ] **Task 5.15**: Run strategy in paper trading mode
  - Full day of trading
  - Verify all decisions logged
  - Verify execution ordering

- [ ] **Task 5.16**: Review audit trail completeness
  - Can answer: "What data led to this trade?"
  - Can answer: "Why did this trade fail?"

---

## Phase 6: Analytics & Reporting (Week 3-4)

**Goal**: Queries, reports, and monitoring  
**Tasks**: 13 | **Completed**: 0/13

### Query Classes

- [ ] **Task 6.1**: Create `SymbolActivityReport` query
  - Location: `packs/audit_trail/app/queries/audit_trail/symbol_activity_report.rb`
  - Implement: data_ingested, decisions_made, trades_executed, summary
  - Target: <200ms for full year query

- [ ] **Task 6.2**: Create `StrategyPerformanceReport` query
  - Location: `packs/audit_trail/app/queries/audit_trail/strategy_performance_report.rb`
  - Compare strategies by success rate
  - Separate signal quality from execution issues

- [ ] **Task 6.3**: Create `FailureAnalysisReport` query
  - Location: `packs/audit_trail/app/queries/audit_trail/failure_analysis_report.rb`
  - Group failures by reason
  - Identify patterns (e.g., always fails on Mondays)

### Rake Tasks

- [ ] **Task 6.4**: Create `audit:symbol_report` rake task
  - Usage: `rake audit:symbol_report[AAPL,2025-01-01,2025-12-31]`
  - Output human-readable summary

- [ ] **Task 6.5**: Create `audit:strategy_performance` rake task
  - Usage: `rake audit:strategy_performance[CongressionalTradingStrategy]`
  - Output success rate, failure breakdown

- [ ] **Task 6.6**: Create `audit:daily_summary` rake task
  - Run automatically after trading day
  - Email/Slack summary of decisions, executions, failures

### Monitoring & Alerts

- [ ] **Task 6.7**: Add alert for zero data ingestion
  - If DataIngestionRun.records_fetched == 0, alert

- [ ] **Task 6.8**: Add alert for high failure rate
  - If >30% trades fail, alert

- [ ] **Task 6.9**: Add alert for API errors
  - If ApiResponse errors > threshold, alert

### Retention Policy

- [ ] **Task 6.10**: Create `maintenance:purge_old_api_payloads` rake task
  - Delete ApiPayload records older than 2 years
  - Run monthly via cron

- [ ] **Task 6.11**: Add cron job for retention policy
  - Schedule: `0 2 1 * *` (monthly at 2 AM)

### Documentation

- [ ] **Task 6.12**: Create audit trail query guide
  - Location: `docs/audit_trail_queries.md`
  - Common queries with examples

- [ ] **Task 6.13**: Update operational runbook
  - Location: `docs/operations/audit_trail.md`
  - How to investigate failed trades
  - How to generate compliance reports

---

## Final Checklist

### Code Quality

- [ ] All tests passing (`bundle exec rspec`)
- [ ] Linter passing (`bundle exec rubocop`)
- [ ] Security scan passing (`bundle exec brakeman --no-pager`)
- [ ] Packwerk validation passing (`bundle exec packwerk validate && packwerk check`)

### Performance

- [ ] Decision creation: <100ms
- [ ] Execution logging: <20ms overhead
- [ ] Symbol activity report: <200ms for full year
- [ ] No N+1 queries (verified with `bullet` gem)

### Documentation

- [ ] All README files updated
- [ ] CONVENTIONS.md updated
- [ ] API documentation (if exposing via API)
- [ ] Runbook for operations team

### Deployment

- [ ] Migrations tested in staging
- [ ] Zero downtime deployment plan
- [ ] Rollback plan documented
- [ ] Feature flag for gradual rollout

### Success Metrics

- [ ] 100% of data ingestion runs logged
- [ ] 100% of trade decisions logged before execution
- [ ] Can answer: "Show me all AAPL activity in 2025" in <200ms
- [ ] Can answer: "What data led to this trade decision?"
- [ ] Can answer: "Why did this trade fail?"
- [ ] Strategy success rate measurable independent of execution issues

---

## Progress Tracking

**Phase 1**: 0/15 tasks (0%)  
**Phase 2**: 0/12 tasks (0%)  
**Phase 3**: 0/18 tasks (0%)  
**Phase 4**: 0/15 tasks (0%)  
**Phase 5**: 0/16 tasks (0%)  
**Phase 6**: 0/13 tasks (0%)  

**Overall**: 0/89 tasks (0%)

---

## Notes

- Mark tasks complete with `[x]` in checkbox
- Add notes/blockers inline as needed
- Update progress tracking section after each task
- Run full test suite after each phase
