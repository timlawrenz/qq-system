# Change Proposal: Trade Outbox Pattern with Audit Trail

**Change ID**: `trade-outbox-pattern`  
**Type**: Feature Addition (Infrastructure)  
**Status**: 📝 Draft  
**Priority**: High (Critical for production readiness)  
**Estimated Effort**: 3-4 weeks  
**Created**: 2024-12-24  

---

## Why

The current trading system lacks comprehensive auditability and traceability, creating regulatory risk and limiting our ability to improve strategies:

**Current Problems:**
- Trade decisions trigger immediate API calls (no record of intent before execution)
- Many BUY orders fail silently due to insufficient buying power
- No persistent record of what data informed each trading decision
- Cannot distinguish "attempted trades" vs "executed trades"
- Data ingestion is untracked (rake tasks run, but we don't know what was fetched)
- Cannot answer: "What AAPL data did we have when we made this trade?"
- Cannot prove we didn't have advance/non-public information

**Regulatory Impact:**
- ❌ Cannot audit trading decisions for SEC/FINRA compliance
- ❌ Cannot prove data timeliness (when it became available)
- ❌ Cannot reconstruct decision rationale after the fact
- ❌ Regulatory risk for automated trading systems (SEC Rule 15c3-5)

**Strategic Impact:**
- ❌ Cannot analyze which data signals drove successful trades
- ❌ Cannot measure strategy quality separate from execution issues
- ❌ Limited ability to improve strategies through post-trade analysis
- ❌ Cannot debug: "Why didn't we trade MSFT yesterday?"

---

## What Changes

### New Capabilities

1. **Data Ingestion Audit Trail**
   - Log every rake task execution with timestamps
   - Track what records were fetched/created/updated
   - Store API call details (endpoints, status codes, rate limits)
   - Link ingested records to specific ingestion runs

2. **Trade Decision Outbox Pattern**
   - Capture trade intent BEFORE execution
   - Store complete decision rationale (signals, context, data sources)
   - Link decisions to source data (QuiverTrade IDs, ingestion runs)
   - Track decision status (pending → executed/failed)

3. **Trade Execution Logging**
   - Log all Alpaca API interactions (request/response)
   - Extract key fields for querying (filled price, quantity, status)
   - Store error details for failed trades
   - NO retry logic (preserves signal strength ordering)

4. **Symbol Activity Reporting**
   - Query: "Show me all AAPL activity in 2025"
   - Returns: data ingested → decisions made → trades executed
   - Performance: <200ms for full year of activity

### Technical Components

**New Pack:** `packs/audit_trail/`
- Models: `DataIngestionRun`, `DataIngestionRunRecord`, `ApiPayload` (STI), `TradeDecision`, `TradeExecution`
- Commands: `LogDataIngestion`, `CreateTradeDecision`, `ExecuteTradeDecision`
- Queries: `SymbolActivityReport`

**Updated Packs:**
- `packs/data_fetching/` - Rake tasks use `LogDataIngestion` command
- `packs/trading_strategies/` - Strategies use `CreateTradeDecision` command

**Database Changes:**
- 5 new tables (see specs/audit-trail/spec.md and detailed docs in /docs/architecture/trade-outbox-pattern/)
- Fully normalized (no JSONB for foreign relationships)
- STI for API payloads (reusable across ingestion and trading)
- Hybrid approach for `TradeDecision.decision_rationale` (FK + JSONB)

### Breaking Changes

**None** - This is purely additive:
- Existing models (QuiverTrade, AlpacaOrder) unchanged
- Strategies continue to work (but should be updated to use new pattern)
- Backward compatibility maintained during migration

### Non-Goals

- Real-time streaming of trade events (can add later)
- Complex event sourcing architecture
- Retry logic for failed trades (preserves signal ordering)
- Automatic order modifications

---

## Success Criteria

### Auditability
- ✅ 100% of data ingestion runs logged with timestamps
- ✅ 100% of trade decisions captured before execution
- ✅ Full API request/response history for every trade
- ✅ Can reconstruct decision rationale 6 months later
- ✅ Can prove when data became available to system

### Visibility
- ✅ Clear separation of "signals generated" vs "trades executed"
- ✅ Failure rate by reason (buying power, API errors, etc.)
- ✅ Strategy success rate independent of execution issues
- ✅ "Show me all AAPL activity in 2025" query works in <200ms

### Performance
- ✅ Data ingestion logging: <50ms overhead per rake task
- ✅ Decision creation: <100ms
- ✅ Synchronous execution: preserves signal ordering
- ✅ Query performance: <500ms for 10K+ records

### Compliance
- ✅ SEC Rule 15c3-5 ready (audit trail for automated trading)
- ✅ Can answer regulator question: "What data did you have at decision time?"
- ✅ Provable data timeliness (no advance knowledge)

---

## Impact Assessment

### Database
- **Storage**: ~26MB/year for aggressive trading (250 days × 20 decisions/day)
- **Write load**: +3-5 INSERTs per trade (acceptable)
- **Query load**: Minimal (indexed columns, efficient JOINs)

### Application
- **Code changes**: Medium (new pack + update 2 existing packs)
- **Performance**: Negligible (<100ms per decision)
- **Complexity**: Low (standard Rails patterns + GLCommand)

### Operations
- **Deployment**: Zero downtime (migrations are additive)
- **Monitoring**: New metrics for ingestion runs, decision success rates
- **Retention**: Need policy for old API payloads (recommend 2 years)

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Increased database load | Medium | GIN indexes on JSONB, composite indexes on FKs |
| Breaking strategies during migration | High | Maintain backward compatibility, update incrementally |
| Polymorphic association performance | Low | Proper eager loading, indexed foreign keys |
| Disk space growth | Low | ~26MB/year, implement retention policy after 2 years |
| Developer learning curve | Low | Standard Rails patterns, clear examples in specs |

---

## Open Questions

1. **Retention Policy**: Keep all records forever, or archive after 2 years?
   - *Recommendation*: Keep 2 years hot, move to cold storage/S3 after
2. **Alert on Failed Trades**: Slack/email for execution failures?
   - *Recommendation*: Yes, alert on insufficient buying power immediately
3. **Manual Orders**: How to handle manually placed trades?
   - *Recommendation*: Create TradeDecision with `strategy_name="manual"`
4. **Ingestion Failures**: Auto-retry failed data fetches?
   - *Recommendation*: Alert only, manual retry to avoid duplicates

---

## Dependencies

### Internal
- Existing packs: `data_fetching`, `trading_strategies`, `trades`, `alpaca_api`
- GLCommand gem (already in use)
- Packwerk (for pack boundaries)

### External
- PostgreSQL 16 (for JSONB + GIN indexes)
- No new gems required

---

## Implementation Plan

See `tasks.md` for detailed checklist.

### Phase 1: Data Ingestion Logging (Week 1)
Quick win - immediate value for debugging and compliance.

### Phase 2: Trade Outbox Tables (Week 1-2)
Database migrations, models, validations.

### Phase 3: Service Layer (Week 2)
GLCommands for decision creation and execution.

### Phase 4: Strategy Integration (Week 2-3)
Update strategies to use new pattern, maintain backward compatibility.

### Phase 5: Testing & Validation (Week 3)
Integration tests, performance testing, manual validation in paper trading.

### Phase 6: Analytics & Reporting (Week 3-4)
Symbol activity reports, dashboard queries, alerts.

---

## References

- [Outbox Pattern (Chris Richardson)](https://microservices.io/patterns/data/transactional-outbox.html)
- [SEC Rule 15c3-5 (Market Access Rule)](https://www.sec.gov/rules/final/2010/34-63241.pdf)
- Current codebase: `packs/trading_strategies/`, `lib/tasks/data_fetch.rake`
- Related: QuiverQuant API docs, Alpaca Trading API docs

---

## Next Steps

1. ✅ Review this proposal
2. ⏳ Review detailed specs in `specs/` directory
3. ⏳ Approve change
4. ⏳ Begin Phase 1 implementation
5. ⏳ Deploy to staging for validation
6. ⏳ Production deployment (zero downtime)
