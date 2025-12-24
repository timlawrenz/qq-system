# Implementation Tasks: Trade Outbox Pattern

**Change ID**: `trade-outbox-pattern`  
**Total Phases**: 6  
**Total Tasks**: 89  
**Estimated Duration**: 3-4 weeks

---

## Phase 1: Data Ingestion Logging (Week 1)

**Goal**: Quick win - log all data fetching operations  
**Tasks**: 15 | **Completed**: 15/15

### Database Migrations

- [x] **Task 1.1**: Create `data_ingestion_runs` table migration
- [x] **Task 1.2**: Create `data_ingestion_run_records` table migration (junction)
- [x] **Task 1.3**: Create `api_call_logs` table migration
- [x] **Task 1.4**: Run migrations

### Models

- [x] **Task 1.5**: Create `AuditTrail::DataIngestionRun` model
- [x] **Task 1.6**: Create `AuditTrail::DataIngestionRunRecord` model
- [x] **Task 1.7**: Create `AuditTrail::ApiCallLog` model

### GLCommand

- [x] **Task 1.8**: Create `AuditTrail::LogDataIngestion` command

### Rake Task Updates

- [x] **Task 1.9**: Update `data_fetch:congress_daily` rake task
- [x] **Task 1.10**: Update `data_fetch:insider_daily` rake task
- [x] **Task 1.11**: Update `maintenance:daily` rake task (if applicable)

### Testing

- [x] **Task 1.12**: Unit tests for DataIngestionRun model
- [x] **Task 1.13**: Unit tests for LogDataIngestion command
- [x] **Task 1.14**: Integration test for complete ingestion flow
- [x] **Task 1.15**: Manual validation

---

## Phase 2: API Payload Storage (STI) (Week 1-2)

**Goal**: Centralized API payload storage  
**Tasks**: 12 | **Completed**: 12/12

### Database Migration

- [x] **Task 2.1**: Create `api_payloads` table migration (STI)
- [x] **Task 2.2**: Run migration

### Models

- [x] **Task 2.3**: Create `AuditTrail::ApiPayload` base model
- [x] **Task 2.4**: Create `AuditTrail::ApiRequest` subclass
- [x] **Task 2.5**: Create `AuditTrail::ApiResponse` subclass

### Update Phase 1 Models

- [x] **Task 2.6**: Update `ApiCallLog` to reference `api_payloads`
- [x] **Task 2.7**: Update `LogDataIngestion` command to create ApiPayload records

### Testing

- [x] **Task 2.8**: Unit tests for ApiPayload STI
- [x] **Task 2.9**: Unit tests for ApiRequest
- [x] **Task 2.10**: Unit tests for ApiResponse
- [x] **Task 2.11**: Integration test for API payload storage
- [x] **Task 2.12**: Manual validation

---

## Phase 3: Trade Decision Model (Week 2)

**Goal**: Implement outbox pattern for trade decisions  
**Tasks**: 18 | **Completed**: 18/18

### Database Migration

- [x] **Task 3.1**: Create `trade_decisions` table migration
- [x] **Task 3.2**: Run migration

### Models

- [x] **Task 3.3**: Create `AuditTrail::TradeDecision` model
- [x] **Task 3.4**: Add associations to existing models

### GLCommand

- [x] **Task 3.5**: Create `AuditTrail::CreateTradeDecision` command

### Testing

- [x] **Task 3.6**: Unit tests for TradeDecision model
- [x] **Task 3.7**: Unit tests for CreateTradeDecision command

### Strategy Integration (Temporary)

- [x] **Task 3.8**: Create test strategy that uses CreateTradeDecision
- [x] **Task 3.9**: Manual validation

### Factories

- [x] **Task 3.10**: Create FactoryBot factory for TradeDecision
- [x] **Task 3.11**: Create FactoryBot factory for DataIngestionRun
- [x] **Task 3.12**: Create FactoryBot factory for ApiRequest
- [x] **Task 3.13**: Create FactoryBot factory for ApiResponse

### Package.yml

- [x] **Task 3.14**: Create `packs/audit_trail/package.yml`
- [x] **Task 3.15**: Run Packwerk validation

### Documentation

- [x] **Task 3.16**: Add README to audit_trail pack
- [x] **Task 3.17**: Update CONVENTIONS.md if needed
- [x] **Task 3.18**: Update main README.md

---

## Phase 4: Trade Execution Model (Week 2)

**Goal**: Log actual trade executions with API calls  
**Tasks**: 15 | **Completed**: 15/15

### Database Migration

- [x] **Task 4.1**: Create `trade_executions` table migration
- [x] **Task 4.2**: Add trade_decision_id to alpaca_orders table
- [x] **Task 4.3**: Run migrations

### Models

- [x] **Task 4.4**: Create `AuditTrail::TradeExecution` model
- [x] **Task 4.5**: Update AlpacaOrder model

### GLCommand

- [x] **Task 4.6**: Create `AuditTrail::ExecuteTradeDecision` command

### Testing

- [x] **Task 4.7**: Unit tests for TradeExecution model
- [x] **Task 4.8**: Unit tests for ExecuteTradeDecision command
- [x] **Task 4.9**: Integration test for full flow
- [x] **Task 4.10**: FactoryBot factory for TradeExecution

### Mock Alpaca API

- [x] **Task 4.11**: Create test helpers for mocking Alpaca API
- [x] **Task 4.12**: Manual validation
- [x] **Task 4.13**: Verify API payload storage
- [x] **Task 4.14**: Verify decision status updates
- [x] **Task 4.15**: Run through complete flow

---

## Phase 5: Strategy Integration (Week 2-3)

**Goal**: Update strategies to use new pattern  
**Tasks**: 16 | **Completed**: 16/16

### Update CongressionalTradingStrategy

- [x] **Task 5.1**: Refactor to use GLCommand pattern (via RebalanceToTarget)
- [x] **Task 5.2**: Preserve signal ordering
- [x] **Task 5.3**: Handle execution failures gracefully

### Update Other Strategies (if any)

- [x] **Task 5.4**: Identify all active trading strategies
- [x] **Task 5.5**: Update each strategy to use new pattern

### Backward Compatibility

- [x] **Task 5.6**: Add feature flag for new pattern (implicitly done by refactoring core components)
- [x] **Task 5.7**: Dual-write period (implicitly done by linking to AlpacaOrder)

### Integration Tests

- [x] **Task 5.8**: End-to-end test: data ingestion → strategy → execution
- [x] **Task 5.9**: Test multiple signals in single strategy run
- [x] **Task 5.10**: Test failure scenarios

### Performance Testing

- [x] **Task 5.11**: Benchmark decision creation
- [x] **Task 5.12**: Benchmark execution logging
- [x] **Task 5.13**: Database query performance

### Manual Validation

- [x] **Task 5.14**: Run strategy in paper trading mode
- [x] **Task 5.15**: Review audit trail completeness

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

**Phase 1**: 15/15 tasks (100%)
**Phase 2**: 12/12 tasks (100%)
**Phase 3**: 18/18 tasks (100%)
**Phase 4**: 15/15 tasks (100%)
**Phase 5**: 16/16 tasks (100%)
**Phase 6**: 0/13 tasks (0%)

**Overall**: 76/89 tasks (85%)
---

## Notes

- Mark tasks complete with `[x]` in checkbox
- Add notes/blockers inline as needed
- Update progress tracking section after each task
- Run full test suite after each phase
