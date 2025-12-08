# Change Proposal: Trading Mode Switch Implementation

**Change ID**: `add-trading-mode-switch`  
**Type**: Safety Feature  
**Status**: Draft  
**Priority**: Critical (Required before live trading)  
**Estimated Effort**: 2-3 hours  
**Created**: 2025-12-08  

---

## Problem Statement

The system currently uses environment variables to connect to Alpaca API, but there's no clear, safe mechanism to switch between paper trading and live trading modes. This creates critical safety risks:

**Current State:**
- `AlpacaService` reads generic `APCA_API_BASE_URL`, `ALPACA_API_KEY_ID`, `ALPACA_API_SECRET_KEY`
- The endpoint defaults to `https://paper-api.alpaca.markets` if not set
- ❌ No validation that credentials match the intended trading mode
- ❌ No audit trail of which mode was used for trades
- ❌ Scripts like `daily_trading.sh` have no mode awareness
- ❌ Easy to accidentally use live credentials with paper endpoint or vice versa

**Impact:**
- **HIGH RISK**: Accidentally trading real money when testing
- **HIGH RISK**: Using wrong API keys with wrong endpoint  
- **MEDIUM RISK**: No audit trail for compliance or debugging
- **MEDIUM RISK**: User confusion about which mode is active

---

## Proposed Solution

Build a safe, explicit trading mode configuration system with:

1. **Single source of truth**: `TRADING_MODE` environment variable (`paper` or `live`)
2. **Mode-specific credentials**: Separate env vars for paper vs live credentials
3. **Safety checks**: Require explicit confirmation for live trading
4. **Audit trail**: Store trading mode in database records
5. **Clear visibility**: Log and display active mode prominently

This unblocks live trading deployment by providing the safety guardrails needed for production.

---

## Requirements

### Functional Requirements

**FR-1**: Trading mode must be explicitly configurable
- Add `TRADING_MODE` environment variable (values: `paper`, `live`)
- Default to `paper` for safety
- Validate mode is one of the allowed values
- Log mode at service initialization

**FR-2**: Credentials must be mode-specific
- Paper mode uses `ALPACA_PAPER_API_KEY_ID` and `ALPACA_PAPER_API_SECRET_KEY`
- Live mode uses `ALPACA_LIVE_API_KEY_ID` and `ALPACA_LIVE_API_SECRET_KEY`
- Validate required credentials are present for selected mode
- Automatically select correct endpoint based on mode

**FR-3**: Live trading must require explicit confirmation
- Live mode requires `CONFIRM_LIVE_TRADING=yes`
- Raise clear safety error if confirmation missing
- Log prominent warning when live mode active

**FR-4**: Trading mode must be auditable
- Add `trading_mode` column to `orders` table
- Add `trading_mode` column to `analyses` table
- Store mode when creating records
- Enable filtering by trading mode

**FR-5**: Scripts must display trading mode
- Update `daily_trading.sh` to show mode prominently
- Display warning banner for live mode
- Make mode visible in all relevant output

### Non-Functional Requirements

**NFR-1**: Safety - Impossible to accidentally enable live trading  
**NFR-2**: Clarity - Trading mode always obvious from logs and output  
**NFR-3**: Auditability - Full history of which mode was used for each trade  
**NFR-4**: Simplicity - Single environment variable controls mode  

---

## Technical Design

### Components

**Affected Files**:
```
packs/alpaca_api/app/services/alpaca_service.rb  # Update
db/migrate/                                       # New migration
daily_trading.sh                                  # Update
spec/services/alpaca_service_spec.rb              # New tests
```

### Configuration Structure

```bash
# Trading Mode (required)
TRADING_MODE=paper  # or 'live'

# Paper Trading Credentials
ALPACA_PAPER_API_KEY_ID=PKxxxxxxxx
ALPACA_PAPER_API_SECRET_KEY=xxxxxxxx

# Live Trading Credentials (optional, only needed for live mode)
ALPACA_LIVE_API_KEY_ID=AKxxxxxxxx
ALPACA_LIVE_API_SECRET_KEY=xxxxxxxx

# Live Trading Safety Confirmation (required for live mode)
CONFIRM_LIVE_TRADING=yes  # Required for TRADING_MODE=live
```

### Key Decisions

- **Default to paper**: Safety first - require explicit opt-in for live trading
- **Separate credentials**: Eliminate possibility of credential/endpoint mismatch
- **Double confirmation**: Both `TRADING_MODE=live` AND `CONFIRM_LIVE_TRADING=yes` required
- **Audit trail**: Store mode in database for compliance and debugging
- **Prominent logging**: Make it impossible to miss which mode is active

### Data Flow

```
Application starts
  ↓
AlpacaService initializes
  ↓
Read TRADING_MODE (default: 'paper')
  ↓
Validate mode is 'paper' or 'live'
  ↓
Select credentials: ALPACA_[PAPER|LIVE]_*
  ↓
Validate credentials present
  ↓
If live mode: Check CONFIRM_LIVE_TRADING=yes
  ↓
Select endpoint based on mode
  ↓
Log mode (WARNING for live, INFO for paper)
  ↓
Create Alpaca client with correct config
  ↓
Store trading_mode when creating Orders/Analyses
```

---

## Implementation Tasks

See `tasks.md` for detailed checklist.

**Summary**:
1. Update AlpacaService with mode detection and validation (1 hour)
2. Add custom error classes (ConfigurationError, SafetyError) (15 min)
3. Create database migration for trading_mode columns (15 min)
4. Update commands to store trading mode (30 min)
5. Update daily_trading.sh with mode display (15 min)
6. Write comprehensive tests (45 min)
7. Update documentation (30 min)

---

## Testing Strategy

### Unit Tests

```ruby
RSpec.describe AlpacaService do
  describe 'paper mode (default)' do
    it 'uses paper endpoint when TRADING_MODE not set'
    it 'uses paper credentials'
    it 'logs paper mode activation'
  end
  
  describe 'paper mode (explicit)' do
    it 'uses paper endpoint when TRADING_MODE=paper'
    it 'validates ALPACA_PAPER_* credentials present'
  end
  
  describe 'live mode' do
    it 'raises error when TRADING_MODE=live without confirmation'
    it 'uses live endpoint when TRADING_MODE=live and confirmed'
    it 'uses live credentials'
    it 'logs prominent warning'
  end
  
  describe 'validation errors' do
    it 'raises ConfigurationError for invalid TRADING_MODE'
    it 'raises ConfigurationError for missing credentials'
    it 'raises SafetyError for live mode without confirmation'
  end
end
```

### Integration Tests

```ruby
RSpec.describe 'Trading Mode End-to-End' do
  it 'stores trading_mode when creating orders'
  it 'stores trading_mode when creating analyses'
  it 'allows filtering orders by trading_mode'
end
```

### Manual Tests

1. **Paper mode (default)**:
   ```bash
   # No TRADING_MODE set
   ./daily_trading.sh
   # Expected: Uses paper endpoint, shows "Mode: PAPER"
   ```

2. **Live mode (without confirmation)**:
   ```bash
   export TRADING_MODE=live
   ./daily_trading.sh
   # Expected: Fails with SafetyError
   ```

3. **Live mode (with confirmation)**:
   ```bash
   export TRADING_MODE=live
   export CONFIRM_LIVE_TRADING=yes
   ./daily_trading.sh
   # Expected: Uses live endpoint, shows red warning banner
   ```

---

## Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Accidentally using live mode | Critical - real money loss | Low | Require CONFIRM_LIVE_TRADING=yes |
| Wrong credentials for mode | High - failed trades | Low | Validate credential prefix matches mode |
| Mode not visible in logs | Medium - user confusion | Medium | Prominent logging at startup |
| No audit trail | Medium - compliance issues | Low | Store trading_mode in database |
| Scripts don't show mode | Medium - user confusion | Medium | Update daily_trading.sh output |
| Forgot to set TRADING_MODE | Low - defaults to paper | N/A | Safe default (paper mode) |

---

## Success Criteria

**Immediate** (Today):
- [ ] AlpacaService implements mode detection and validation
- [ ] Database migration adds trading_mode columns
- [ ] All tests passing (unit + integration)
- [ ] Documentation updated

**Short-term** (Week 1):
- [ ] Paper mode tested with real trades
- [ ] Live mode confirmation tested (should block)
- [ ] Audit trail verified in database
- [ ] Script output shows mode clearly

**Long-term** (Before live trading):
- [ ] Safety checklist from spec completed
- [ ] 30+ days of successful paper trading logged
- [ ] Team trained on mode switching procedure
- [ ] Emergency rollback procedure documented and tested

---

## Dependencies

- ✅ AlpacaService (already exists)
- ✅ PostgreSQL database (already configured)
- ✅ Orders and Analyses tables (already exist)
- ⚠️ Alpaca live API credentials (must obtain before going live)

---

## Deployment Plan

**Phase 1**: Implementation (Today)
- Implement AlpacaService changes
- Add database migration
- Update scripts
- Write tests

**Phase 2**: Paper Trading Validation (Week 1)
- Run daily_trading.sh in paper mode
- Verify mode is logged correctly
- Confirm audit trail in database

**Phase 3**: Pre-Live Preparation (Weeks 2-6)
- Complete 30+ days paper trading
- Complete safety checklist from spec
- Obtain live API credentials
- Document rollback procedures

**Phase 4**: Live Trading Deployment (Week 7+)
- Set TRADING_MODE=live and CONFIRM_LIVE_TRADING=yes
- Start with minimal position sizes
- Monitor closely for 1 week
- Gradually increase to target sizes

---

## Migration Path

### Current State → Paper Mode (Explicit)
1. Set `TRADING_MODE=paper` (optional, already default)
2. Rename env vars: `ALPACA_API_KEY_ID` → `ALPACA_PAPER_API_KEY_ID`
3. Restart services
4. Verify mode in logs

### Paper Mode → Live Mode
1. **Prerequisites**: Complete safety checklist
2. Obtain live API credentials from Alpaca
3. Set `ALPACA_LIVE_API_KEY_ID` and `ALPACA_LIVE_API_SECRET_KEY`
4. Set `TRADING_MODE=live`
5. Set `CONFIRM_LIVE_TRADING=yes`
6. Restart services
7. Verify mode in logs (should see 🚨 LIVE TRADING MODE ACTIVE 🚨)
8. Test with minimal position first

### Emergency: Live Mode → Paper Mode
1. Set `TRADING_MODE=paper` (or unset TRADING_MODE)
2. Restart services immediately
3. Verify mode switch in logs
4. Test trade execution
5. Investigate issue that triggered rollback

---

## Open Questions

1. **Data retention**: Keep both paper and live trades in same tables?  
   → **Yes** - `trading_mode` column allows filtering

2. **Separate databases**: Use different databases for paper vs live?  
   → **No** - Single database, filter by `trading_mode` column

3. **API cost**: Live trading API rate limits?  
   → **Verify with Alpaca** - document in README

4. **Monitoring**: Different alerts for paper vs live?  
   → **Future enhancement** - start with same monitoring

5. **Position limits**: Different max sizes for paper vs live?  
   → **Future enhancement** - start with same limits

---

## Related Specs

- Primary spec: `openspec/specs/trading-mode-switch.md`
- Related: `daily_trading.sh` script
- Related: `packs/alpaca_api/app/services/alpaca_service.rb`

---

## Approval

- [ ] Technical design reviewed
- [ ] Safety requirements approved
- [ ] Timeline accepted  
- [ ] Dependencies verified
- [ ] Live API credentials plan confirmed

**Ready for implementation**: Pending approval

---

**Target Completion**: 1 day (2-3 hours implementation)  
**Unblocks**: Live trading deployment (critical for production)  
**Risk Level**: Critical safety feature - must implement before live trading
