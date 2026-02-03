---
title: "Trading Mode Switch: Paper vs Live Trading"
type: spec
status: draft
priority: high
created: 2025-12-08
estimated_effort: 2-3 hours
tags:
  - configuration
  - trading
  - safety
  - risk-management
---

# OpenSpec: Trading Mode Switch

## Metadata
- **Author**: GitHub Copilot
- **Date**: 2025-12-08
- **Status**: Draft
- **Priority**: High (Required before live trading)
- **Estimated Effort**: 2-3 hours

---

## Problem Statement

The system currently uses environment variables to connect to Alpaca API, but there's no clear, safe mechanism to switch between paper trading and live trading modes. This creates risks:

**Current State:**
- `AlpacaService` reads `APCA_API_BASE_URL`, `ALPACA_API_KEY_ID`, `ALPACA_API_SECRET_KEY`
- The endpoint defaults to `https://paper-api.alpaca.markets` if not set
- No validation that credentials match the intended trading mode
- Easy to accidentally use live credentials with paper endpoint or vice versa

**Risks:**
- Accidentally trading real money when testing
- Using wrong API keys with wrong endpoint
- No audit trail of which mode was used for trades
- Scripts like `daily_trading.sh` have no mode awareness

---

## Goals

1. **Primary**: Provide a clear, explicit trading mode configuration
2. **Secondary**: Add safety checks to prevent credential/endpoint mismatches
3. **Tertiary**: Enable easy mode switching without editing multiple files

**Success Criteria:**
- Single environment variable controls trading mode
- System validates credentials match the selected mode
- Logs clearly indicate which mode is active
- Scripts show mode in output
- Cannot accidentally use live trading without explicit opt-in

---

## Proposed Solution

### 1. Trading Mode Configuration

Add a `TRADING_MODE` environment variable with two values:
- `paper` (default, safe)
- `live` (explicit opt-in)

### 2. Environment Variable Structure

```bash
# Trading Mode (required)
TRADING_MODE=paper  # or 'live'

# Paper Trading Credentials
ALPACA_PAPER_API_KEY_ID=PKxxxxxxxx
ALPACA_PAPER_API_SECRET_KEY=xxxxxxxx

# Live Trading Credentials (optional, only needed for live mode)
ALPACA_LIVE_API_KEY_ID=AKxxxxxxxx
ALPACA_LIVE_API_SECRET_KEY=xxxxxxxx
```

### 3. AlpacaService Enhancement

```ruby
class AlpacaService
  PAPER_ENDPOINT = 'https://paper-api.alpaca.markets'
  LIVE_ENDPOINT = 'https://api.alpaca.markets'
  
  def initialize
    @trading_mode = ENV.fetch('TRADING_MODE', 'paper').downcase
    validate_trading_mode!
    
    @client = Alpaca::Trade::Api::Client.new(
      endpoint: endpoint,
      key_id: api_key_id,
      key_secret: api_secret_key
    )
    
    log_trading_mode
  end
  
  private
  
  def validate_trading_mode!
    unless %w[paper live].include?(@trading_mode)
      raise ConfigurationError, "Invalid TRADING_MODE: #{@trading_mode}. Must be 'paper' or 'live'"
    end
    
    # Validate credentials are present
    raise ConfigurationError, "Missing #{credential_prefix}_API_KEY_ID" if api_key_id.blank?
    raise ConfigurationError, "Missing #{credential_prefix}_API_SECRET_KEY" if api_secret_key.blank?
    
    # Safety check: Require explicit live mode confirmation
    if @trading_mode == 'live' && ENV['CONFIRM_LIVE_TRADING'] != 'yes'
      raise SafetyError, "Live trading requires CONFIRM_LIVE_TRADING=yes"
    end
  end
  
  def endpoint
    @trading_mode == 'live' ? LIVE_ENDPOINT : PAPER_ENDPOINT
  end
  
  def credential_prefix
    @trading_mode == 'live' ? 'ALPACA_LIVE' : 'ALPACA_PAPER'
  end
  
  def api_key_id
    ENV["#{credential_prefix}_API_KEY_ID"]
  end
  
  def api_secret_key
    ENV["#{credential_prefix}_API_SECRET_KEY"]
  end
  
  def log_trading_mode
    Rails.logger.warn("🚨 LIVE TRADING MODE ACTIVE 🚨") if @trading_mode == 'live'
    Rails.logger.info("Trading mode: #{@trading_mode.upcase} | Endpoint: #{endpoint}")
  end
end
```

### 4. Script Updates

Update `daily_trading.sh` to show trading mode:

```bash
# At the start
TRADING_MODE=${TRADING_MODE:-paper}
echo "================================================================"
echo " QuiverQuant Daily Trading Script"
echo " Mode: ${TRADING_MODE^^}"
if [ "$TRADING_MODE" = "live" ]; then
  echo -e " ${RED}⚠ LIVE TRADING - REAL MONEY ⚠${NC}"
fi
echo "================================================================"
```

### 5. Database Audit Trail

Add `trading_mode` to relevant tables:

```ruby
# Migration
class AddTradingModeToTables < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :trading_mode, :string, default: 'paper', null: false
    add_column :analyses, :trading_mode, :string, default: 'paper', null: false
    
    add_index :orders, :trading_mode
    add_index :analyses, :trading_mode
  end
end
```

Store mode when creating records:

```ruby
# In Trades::RebalanceToTarget or similar
trading_mode = ENV.fetch('TRADING_MODE', 'paper')
order = Order.create!(
  symbol: symbol,
  side: side,
  qty: qty,
  trading_mode: trading_mode,
  # ... other fields
)
```

---

## Implementation Steps

### Phase 1: Core Configuration (1 hour)
1. Update `AlpacaService` with mode detection and validation
2. Add safety checks for live trading
3. Update logging to show trading mode
4. Add custom error classes (`ConfigurationError`, `SafetyError`)

### Phase 2: Script & UI Updates (30 minutes)
1. Update `daily_trading.sh` to display trading mode
2. Add mode indicator to script output
3. Add colored warnings for live mode

### Phase 3: Audit Trail (30 minutes)
1. Create migration for `trading_mode` columns
2. Update commands to store trading mode
3. Add queries to filter by trading mode

### Phase 4: Testing & Documentation (30 minutes)
1. Test paper mode (default behavior)
2. Test live mode validation (should require confirmation)
3. Test credential validation
4. Update README with configuration instructions
5. Document how to switch modes safely

---

## Testing Strategy

### Unit Tests
```ruby
RSpec.describe AlpacaService do
  context 'paper mode (default)' do
    it 'uses paper endpoint and credentials'
    it 'logs paper mode activation'
  end
  
  context 'live mode' do
    it 'requires TRADING_MODE=live'
    it 'requires CONFIRM_LIVE_TRADING=yes'
    it 'uses live endpoint and credentials'
    it 'logs live mode warning'
  end
  
  context 'validation' do
    it 'raises error for invalid mode'
    it 'raises error for missing credentials'
    it 'raises error for live mode without confirmation'
  end
end
```

### Manual Testing
1. **Paper mode (default)**:
   ```bash
   # No TRADING_MODE set
   ./daily_trading.sh
   # Should: Use paper endpoint, show "Mode: PAPER"
   ```

2. **Paper mode (explicit)**:
   ```bash
   export TRADING_MODE=paper
   ./daily_trading.sh
   # Should: Use paper endpoint, show "Mode: PAPER"
   ```

3. **Live mode (without confirmation)**:
   ```bash
   export TRADING_MODE=live
   ./daily_trading.sh
   # Should: Fail with safety error
   ```

4. **Live mode (with confirmation)**:
   ```bash
   export TRADING_MODE=live
   export CONFIRM_LIVE_TRADING=yes
   ./daily_trading.sh
   # Should: Use live endpoint, show "Mode: LIVE" with red warning
   ```

---

## Configuration Examples

### Development (.env.development)
```bash
# Always paper mode in development
TRADING_MODE=paper
ALPACA_PAPER_API_KEY_ID=PKxxxxxxxx
ALPACA_PAPER_API_SECRET_KEY=xxxxxxxx
```

### Production (.env.production) - Paper Trading
```bash
# Paper trading in production (safe testing)
TRADING_MODE=paper
ALPACA_PAPER_API_KEY_ID=PKxxxxxxxx
ALPACA_PAPER_API_SECRET_KEY=xxxxxxxx
```

### Production (.env.production) - Live Trading
```bash
# Live trading (use with extreme caution)
TRADING_MODE=live
CONFIRM_LIVE_TRADING=yes
ALPACA_LIVE_API_KEY_ID=AKxxxxxxxx
ALPACA_LIVE_API_SECRET_KEY=xxxxxxxx

# Keep paper credentials for quick testing
ALPACA_PAPER_API_KEY_ID=PKxxxxxxxx
ALPACA_PAPER_API_SECRET_KEY=xxxxxxxx
```

---

## Safety Checklist

Before enabling live trading:
- [ ] Test all strategies in paper mode for at least 30 days
- [ ] Verify position sizing is appropriate for account size
- [ ] Review all historical trades for accuracy
- [ ] Set up monitoring and alerts
- [ ] Document rollback procedure
- [ ] Verify stop-loss and risk management rules
- [ ] Test error handling with invalid trades
- [ ] Review and approve maximum position sizes
- [ ] Set up daily reconciliation process
- [ ] Have manual override mechanism ready

---

## Migration Path

### Current State → Paper Mode (Explicit)
No changes needed - already using paper by default

### Paper Mode → Live Mode
1. Verify 30+ days of successful paper trading
2. Complete safety checklist
3. Set `TRADING_MODE=live` and `CONFIRM_LIVE_TRADING=yes`
4. Test with minimal position size first
5. Gradually increase to target sizes

### Live Mode → Paper Mode (Emergency)
1. Set `TRADING_MODE=paper`
2. Restart services
3. Verify mode switch in logs
4. Test trade execution

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Accidentally using live mode | High - real money loss | Require `CONFIRM_LIVE_TRADING=yes` |
| Wrong credentials for mode | Medium - failed trades | Validate credential prefix matches mode |
| Mode not logged | Low - audit issues | Log mode at service initialization |
| Scripts don't show mode | Medium - user confusion | Display mode prominently in script output |
| No audit trail | Medium - compliance | Store `trading_mode` in database records |

---

## Future Enhancements

1. **Dry-run mode**: Simulate trades without API calls
2. **Mode-specific limits**: Different position sizes for paper vs live
3. **Automatic paper→live promotion**: After X successful days
4. **Web UI toggle**: Switch modes from admin interface
5. **Mode-aware monitoring**: Different alerts for paper vs live
6. **Automated safety checks**: Validate account balance before live trades

---

## References

- Alpaca API Documentation: https://docs.alpaca.markets/
- Paper Trading Endpoint: `https://paper-api.alpaca.markets`
- Live Trading Endpoint: `https://api.alpaca.markets`
- Current implementation: `packs/alpaca_api/app/services/alpaca_service.rb`
- Related script: `daily_trading.sh`

---

## Approval

- [ ] Technical review complete
- [ ] Security review complete
- [ ] Safety checklist approved
- [ ] Documentation updated
- [ ] Tests passing
- [ ] Ready for implementation
