---
title: "Implement FetchQuiverData Command and FetchQuiverDataJob"
type: proposal
status: draft
priority: critical
created: 2025-11-04
estimated_effort: 4-6 hours
tags:
  - data-fetching
  - quiver-api
  - background-jobs
  - critical
---

# OpenSpec Proposal: FetchQuiverData Command & Job

## Metadata
- **Author**: GitHub Copilot
- **Date**: 2025-11-04
- **Status**: Proposal
- **Priority**: Critical (Blocks paper trading)
- **Estimated Effort**: 4-6 hours

---

## Problem Statement

The trading system currently lacks the ability to fetch fresh congressional trading data from the QuiverQuant API and persist it to the database. This creates a critical gap in the data pipeline.

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

## Requirements

### Functional Requirements

**FR-1**: FetchQuiverData command must fetch congressional trades from QuiverQuant API
- MUST use existing QuiverClient service
- MUST support date range filtering (start_date, end_date)
- MUST support optional ticker filtering
- MUST return counts (total, new, updated, errors)

**FR-2**: FetchQuiverData command must persist trades to database
- MUST deduplicate using composite key (ticker + trader_name + transaction_date)
- MUST use find_or_initialize_by for idempotency
- MUST update existing trades if data changed
- MUST continue processing on individual trade failures

**FR-3**: FetchQuiverDataJob must wrap the command for background execution
- MUST accept optional parameters (start_date, end_date, ticker)
- MUST default to 60 days of data when no parameters provided
- MUST retry on failure with exponential backoff (3 attempts)
- MUST log structured output for monitoring

### Non-Functional Requirements

**NFR-1**: Performance
- MUST complete within 30 seconds for typical daily fetch
- MUST handle up to 1000 trades in single fetch

**NFR-2**: Reliability
- MUST be idempotent (safe to run multiple times)
- MUST not corrupt data on failure
- MUST log all errors with context

**NFR-3**: Observability
- MUST log start/end of execution
- MUST log counts (new/updated/errors)
- MUST warn if error rate > 10%

---

## Technical Design

See full implementation details in complete proposal document (730 lines).

### Components

1. **FetchQuiverData** - GLCommand in `packs/data_fetching/app/commands/`
2. **FetchQuiverDataJob** - Background job in `packs/data_fetching/app/jobs/`

### Key Decisions

- **Composite Key**: ticker + trader_name + transaction_date for deduplication
- **Error Strategy**: Continue on individual failures, fail fast on API errors
- **Retry Logic**: 3 attempts with exponential backoff
- **Logging**: Structured with SUCCESS/FAILED markers

---

## Implementation Plan

**Total Effort**: 4-6 hours

### Phase 1: Build FetchQuiverData Command (2-3 hours)
- Create command file
- Implement core logic
- Add error handling
- Write unit tests
- Manual testing in console

### Phase 2: Build FetchQuiverDataJob (1 hour)
- Create job file
- Implement retry logic
- Add structured logging
- Write job specs
- Manual testing

### Phase 3: Integration & Documentation (1-2 hours)
- Write integration test
- Update pack READMEs
- Create rake task
- Document in main README

### Phase 4: End-to-End Validation (1 hour)
- Populate database
- Run ExecuteSimpleStrategyJob
- Verify orders in Alpaca paper account
- Validate complete workflow

---

## Testing Strategy

### Unit Tests
- `fetch_quiver_data_spec.rb` - Command logic
- `fetch_quiver_data_job_spec.rb` - Job wrapper

### Integration Tests  
- End-to-end flow from API to database

### Manual Tests
- Console execution
- Idempotency verification
- Error scenario testing

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| API rate limits | Respect 60 req/min, exponential backoff |
| Auth failure | Validate credentials, clear error messages |
| Duplicate data | Composite unique key, find_or_initialize_by |
| Job doesn't run | Monitoring + alerting |

---

## Success Metrics

**Immediate**: 
- [ ] Tests passing
- [ ] Manual execution works

**Week 1**:
- [ ] Daily manual execution reliable
- [ ] Paper trading using fresh data

**Month 1**:
- [ ] Automated scheduling
- [ ] 99%+ success rate

---

## Dependencies

- QuiverClient (already implemented)
- QuiverTrade model (already exists)
- QuiverQuant API credentials

---

## Approval

- [ ] Technical design approved
- [ ] Timeline accepted
- [ ] API credentials available

---

**Target Completion**: End of day 2025-11-04

**Unblocks**: Paper trading (critical path to live trading)

---

*Full detailed proposal with complete implementation code available in project docs.*
