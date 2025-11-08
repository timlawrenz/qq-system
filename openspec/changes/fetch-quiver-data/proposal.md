# Change Proposal: FetchQuiverData Implementation

**Change ID**: `fetch-quiver-data`  
**Type**: Feature Addition  
**Status**: Draft  
**Priority**: Critical  
**Estimated Effort**: 4-6 hours  
**Created**: 2025-11-04  

---

## Problem Statement

The trading system currently lacks the ability to fetch fresh congressional trading data from the QuiverQuant API and persist it to the database. This creates a critical gap in the data pipeline:

**Current State:**
- ❌ QuiverQuant API (no fetch mechanism)
- ❌ QuiverTrade database table (empty/stale)
- ✅ GenerateTargetPortfolio (reads from DB)
- ✅ RebalanceToTarget (executes trades)

**Impact:**
- ExecuteSimpleStrategyJob reads from QuiverTrade table, but nothing populates it
- Paper trading cannot start without fresh data  
- Manual data imports are not sustainable for production

---

## Proposed Solution

Build two components:

1. **FetchQuiverData command** - GLCommand to fetch from API and persist to database
2. **FetchQuiverDataJob** - Background job wrapper with retry logic

This unblocks paper trading and enables automated daily data refresh.

---

## Requirements

### Functional Requirements

**FR-1**: FetchQuiverData command must fetch congressional trades from API
- Use existing QuiverClient service
- Support date range filtering (start_date, end_date)
- Support optional ticker filtering
- Return counts (total, new, updated, errors)

**FR-2**: Command must persist trades to database
- Deduplicate using composite key (ticker + trader_name + transaction_date)
- Use find_or_initialize_by for idempotency
- Update existing trades if data changed
- Continue processing on individual trade failures

**FR-3**: FetchQuiverDataJob must provide background execution
- Accept optional parameters (start_date, end_date, ticker)
- Default to 60 days when no parameters provided
- Retry on failure with exponential backoff (3 attempts)
- Log structured output for monitoring

### Non-Functional Requirements

**NFR-1**: Performance - Complete within 30 seconds for typical daily fetch  
**NFR-2**: Reliability - Idempotent, safe to retry, no data corruption  
**NFR-3**: Observability - Structured logging with SUCCESS/FAILED markers  

---

## Technical Design

### Components

**Location**: `packs/data_fetching/app/`

```
packs/data_fetching/
├── app/
│   ├── commands/
│   │   └── fetch_quiver_data.rb      # New
│   └── jobs/
│       └── fetch_quiver_data_job.rb  # New
└── spec/
    ├── commands/
    │   └── fetch_quiver_data_spec.rb # New
    └── jobs/
        └── fetch_quiver_data_job_spec.rb # New
```

### Key Decisions

- **Composite Key**: ticker + trader_name + transaction_date
- **Error Strategy**: Fail fast on API errors, continue on individual trade errors
- **Retry Logic**: 3 attempts with exponential backoff (1s, 2s, 4s)
- **Logging**: Structured with clear SUCCESS/FAILED markers

### Data Flow

```
FetchQuiverDataJob.perform_now
  ↓
FetchQuiverData.call
  ↓
QuiverClient.fetch_congressional_trades (existing)
  ↓
Process each trade (find_or_initialize_by)
  ↓
QuiverTrade.save!
  ↓
Return counts (new: X, updated: Y, errors: Z)
```

---

## Implementation Tasks

See `tasks.md` for detailed checklist.

**Summary**:
1. Implement FetchQuiverData command (2-3 hours)
2. Implement FetchQuiverDataJob (1 hour)
3. Write tests (unit + integration) (1 hour)
4. Update documentation (1 hour)
5. End-to-end validation (1 hour)

---

## Testing Strategy

### Unit Tests
- Command: Success path, deduplication, error handling, edge cases
- Job: Execution, retry logic, logging

### Integration Test
- End-to-end: API → Database → ExecuteSimpleStrategyJob

### Manual Tests
- Console execution
- Idempotency verification
- Error scenarios

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| API rate limits (60/min) | High | Respect limits, exponential backoff |
| Auth failure | High | Validate credentials, clear errors |
| Duplicate data | High | Composite unique key |
| Job doesn't run on schedule | High | Monitoring + manual backup |
| Stale data not noticed | Medium | Data freshness check |

---

## Success Criteria

**Immediate** (Today):
- [ ] FetchQuiverData command implemented and tested
- [ ] FetchQuiverDataJob implemented and tested
- [ ] Manual execution successfully populates database
- [ ] All tests passing (unit + integration)

**Short-term** (Week 1):
- [ ] Daily manual execution working reliably
- [ ] ExecuteSimpleStrategyJob uses fresh data
- [ ] Paper trading generates orders successfully
- [ ] No data quality issues observed

**Long-term** (Month 1):
- [ ] Automated scheduling in production
- [ ] 99%+ job success rate
- [ ] Data freshness < 24 hours always
- [ ] Zero manual interventions needed

---

## Dependencies

- ✅ QuiverClient (already implemented)
- ✅ QuiverTrade model (already exists)
- ⚠️ QuiverQuant API credentials (must verify availability)

---

## Deployment Plan

**Phase 1**: Development (Manual execution)
**Phase 2**: Paper Trading (Daily manual runs)
**Phase 3**: Automation (Cron or SolidQueue recurring jobs)
**Phase 4**: Production (Full monitoring + alerting)

---

## Open Questions

1. **Data retention**: Keep all historical data? → **Yes** (disk cheap, useful for backtesting)
2. **Backfill**: Fetch beyond 60 days initially? → **Yes** (1 year for robust backtesting)
3. **API cost**: Cost per call? → **Verify with QuiverQuant**
4. **Data validation**: Quality checks? → **Optional for v1**

---

## Approval

- [ ] Technical design reviewed
- [ ] Timeline accepted  
- [ ] Dependencies verified
- [ ] API credentials confirmed

**Ready for implementation**: Pending approval

---

**Target Completion**: End of day 2025-11-04  
**Unblocks**: Paper trading (critical path to live trading)
