# CRITICAL: Account Safety Issue - Immediate Action Required

**Date**: December 11, 2025  
**Severity**: 🔴 **CRITICAL** - Risk of trading on wrong account  
**Status**: ⚠️ **IDENTIFIED - REQUIRES IMMEDIATE FIX**

---

## The Problem

**Multiple places in code create `AlpacaService.new` and read `ENV['TRADING_MODE']` at runtime.**

This means:
1. ❌ No single source of truth for which account is being used
2. ❌ Different parts of code could connect to different accounts
3. ❌ Default fallback to 'paper' means code might think it's in paper when it's live
4. ❌ Strategies independently fetch account equity - could mix accounts

---

## Current Dangerous Pattern

```ruby
# DANGER: Each strategy does this independently
def fetch_account_equity
  alpaca_service = AlpacaService.new  # ← Reads ENV['TRADING_MODE'] NOW
  alpaca_service.account_equity       # ← Could be paper OR live!
end
```

**Problem**: If `TRADING_MODE` changes between strategy calls, or isn't set, different strategies could use different accounts!

---

## Where This Happens

**Every strategy command** has this pattern:
- `GenerateEnhancedCongressionalPortfolio` (line 72-74)
- `GenerateLobbyingPortfolio` (line 133-135)
- `GenerateInsiderMimicryPortfolio` (line 68-70) ← **NEW - WE JUST ADDED THIS!**
- `GenerateTargetPortfolio` (line 53-55)
- `GenerateBlendedPortfolio` (line 163-165)

Each one calls `AlpacaService.new` independently!

---

## Correct Architecture

### Principle: **ONE Data Loader, ZERO Assumptions**

```ruby
# ✅ CORRECT: Daily script loads data ONCE
equity = load_account_data_once(trading_mode)  # ONE place

# ✅ CORRECT: Pass equity to strategies
result = TradingStrategies::GenerateBlendedPortfolio.call(
  trading_mode: trading_mode,  # For config selection
  total_equity: equity          # ← Explicit, no assumptions
)

# ✅ CORRECT: Strategies NEVER call AlpacaService
def call
  equity = context.total_equity  # ← Must be provided
  raise 'total_equity required' if equity.nil?  # ← Fail loudly
  # ... rest of strategy
end
```

---

## Required Fix

### Step 1: Modify daily_trading.sh

```bash
# Load account data ONCE at the start
EQUITY=$(bundle exec rails runner "
  service = AlpacaService.new
  puts service.account_equity
")

# Pass to blended portfolio
bundle exec rails runner "
  result = TradingStrategies::GenerateBlendedPortfolio.call(
    trading_mode: '${TRADING_MODE}',
    total_equity: ${EQUITY}  # ← Explicit
  )
  # ... rest
"
```

### Step 2: Make total_equity REQUIRED

```ruby
# In ALL strategy commands
def call
  # Remove fallback to fetch_account_equity
  equity = context.total_equity
  
  if equity.nil? || equity <= 0
    stop_and_fail!('total_equity parameter is required')
  end
  
  # ... rest of strategy logic
end

# DELETE these methods entirely
# def fetch_account_equity
#   alpaca_service = AlpacaService.new  # ← DANGEROUS
#   alpaca_service.account_equity
# end
```

### Step 3: Add Safety Checks

```ruby
# In AlpacaService.initialize
def initialize
  @trading_mode = ENV.fetch('TRADING_MODE')  # ← No default!
  # Will raise KeyError if not set
  
  validate_trading_mode!
  # ... rest
end
```

---

## Testing the Fix

### Before Fix (DANGEROUS)
```bash
# What happens if TRADING_MODE gets unset mid-execution?
$ TRADING_MODE=live ./daily_trading.sh

# Strategy 1: Creates AlpacaService.new
#   ENV['TRADING_MODE'] = 'live' → Uses LIVE account ✓

# ... something unsets TRADING_MODE ...

# Strategy 2: Creates AlpacaService.new  
#   ENV['TRADING_MODE'] = nil → Defaults to 'paper' → Uses PAPER account ✗
#   ^^^ NOW TRADING ON WRONG ACCOUNT! ^^^
```

### After Fix (SAFE)
```bash
$ TRADING_MODE=live ./daily_trading.sh

# ONE AlpacaService created at start
# Equity fetched ONCE: $1,006.64 from LIVE account

# All strategies receive: total_equity: 1006.64
# No strategy can create AlpacaService
# No strategy can fetch different equity
# ✓ Impossible to mix accounts
```

---

## Verification Checklist

- [ ] Remove ALL `fetch_account_equity` methods from strategy commands
- [ ] Make `total_equity` a REQUIRED parameter (no default, no fallback)
- [ ] Update `daily_trading.sh` to fetch equity ONCE and pass it
- [ ] Remove default value from `ENV.fetch('TRADING_MODE')` in AlpacaService
- [ ] Add explicit validation that total_equity is provided
- [ ] Test that strategies FAIL LOUDLY if total_equity is missing
- [ ] Document that strategies MUST receive equity, NEVER fetch it

---

## Why This Matters

**Paper account**: ~$100,000  
**Live account**: ~$1,000

If code accidentally mixes accounts:
- Could size positions for $100k account and execute on $1k account
- Could generate positions from $1k account data but execute on $100k account
- Could partially use one account, partially use another

**This is a financial safety issue that could cause real monetary loss.**

---

## Immediate Action

1. **DO NOT RUN LIVE TRADING** until this is fixed
2. Fix all strategy commands to require `total_equity`
3. Update `daily_trading.sh` to pass explicit equity
4. Remove all `AlpacaService.new` calls from strategies
5. Test thoroughly in paper mode
6. Add integration test that verifies account isolation

---

**Next Steps**: See `docs/fixes/ACCOUNT_SAFETY_FIX.md` for implementation plan

**Priority**: 🔴 **CRITICAL** - Must fix before any live trading
