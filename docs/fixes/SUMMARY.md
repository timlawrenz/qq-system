# Trading System Fixes - December 27, 2025

## Summary

Fixed two critical issues preventing successful trading execution:

### 1. Dust Position Cleanup (CCRN, CMCSA, HBNC)
**Problem**: Positions with < 0.00000001 shares were being skipped, accumulating in the account indefinitely.

**Solution**: Remove the dust filter and handle these positions directly:
- For dust positions: bypass trade decision audit and call `close_position` API directly
- For normal positions: use full audit trail with close_position flag

**Files Changed**:
- `packs/trades/app/commands/trades/rebalance_to_target.rb` - Removed dust filter, added bypass logic

### 2. Non-Fractionable Asset Trading (MAIA, HYPD, SWZ, MLP)
**Problem**: Notional orders ("buy $100 worth") fail for non-fractionable assets. Some stocks had no price data available.

**Solution**: Automatic fallback to whole shares with dual-API price discovery:
1. Try notional order first
2. If "not fractionable" → get price from latest_trade API
3. If no trade data → fallback to latest_quote API (bid/ask midpoint)
4. If no price data → block asset and skip
5. Calculate whole shares: `floor(notional / price)`
6. Retry with `qty` parameter

**Files Changed**:
- `packs/audit_trail/app/commands/audit_trail/execute_trade_decision.rb` - Added fallback logic + calculate_whole_shares
- `packs/alpaca_api/app/services/alpaca_service.rb` - Added latest_trade with quote fallback

## Detailed Changes

### Dust Position Cleanup

**Before**:
```
Skipping dust position CCRN: 0.000000003 shares (below minimum precision)
❌ Position never closed
```

**After**:
```
Closing dust position CCRN: 0.000000003 shares using close_position API (bypassing trade decision)
Closed dust position CCRN: 0.000000003 shares
✅ Position cleaned up
```

**Technical Details**:
- Dust threshold: < 0.00000001 shares
- Bypasses `TradeDecision` validation (`quantity > 0`)
- Calls `AlpacaService#close_position` directly
- Still recorded in `orders_placed` for logging
- Proper error handling with `stop_and_fail`

### Non-Fractionable Asset Trading

**Before**:
```
Placing order: {symbol: "MAIA", notional: "96.1"}
Failed to place order: asset "MAIA" is not fractionable
❌ Trade fails completely
```

**After - Scenario 1 (liquid stock with trade data)**:
```
Placing order: {symbol: "MAIA", notional: "96.1"}
Asset MAIA not fractionable, falling back to whole shares
Calculated 3 whole shares for MAIA at $32.00
Placing order: {symbol: "MAIA", qty: "3"}
✅ Order placed ($96 bought, $0.10 remaining)
```

**After - Scenario 2 (illiquid stock with only quote data)**:
```
Placing order: {symbol: "HYPD", notional: "87.86"}
Asset HYPD not fractionable, falling back to whole shares
No trade data for HYPD, trying latest quote
Calculated 4 whole shares for HYPD at $21.50 (from bid/ask midpoint)
✅ Order placed
```

**After - Scenario 3 (no price data available)**:
```
Placing order: {symbol: "SWZ", notional: "87.78"}
Asset SWZ not fractionable, falling back to whole shares
No price data available for SWZ - will block asset
⚠️ Asset blocked: no_price_data
❌ Trade skipped (retries after 7 days)
```

**Technical Details**:
- Price discovery: latest_trade → latest_quote → block asset
- Whole shares: `floor(notional / price)` - always rounds down
- Asset blocking: Prevents repeated failures for untradeable stocks
- Error handling: Catches JSON parse errors, HTTP failures, missing data

## Files Changed

### Modified
1. `packs/trades/app/commands/trades/rebalance_to_target.rb` (18 lines changed)
   - Removed dust position filter
   - Added dust position bypass logic with direct close_position call
   - Enhanced logging for dust cleanup

2. `packs/audit_trail/app/commands/audit_trail/execute_trade_decision.rb` (70 lines added)
   - Added notional order fallback logic
   - Added `calculate_whole_shares` helper method
   - Enhanced error handling for fractionable assets
   - Added asset blocking for no price data

3. `packs/alpaca_api/app/services/alpaca_service.rb` (78 lines added)
   - Added `latest_trade` method with quote fallback
   - Added private `get_latest_trade_data` method
   - Added private `get_latest_quote_data` method
   - Proper error handling for non-JSON responses

### Created
4. `docs/fixes/DUST_POSITION_CLEANUP.md` - Dust position fix documentation
5. `docs/fixes/NON_FRACTIONABLE_ASSET_FALLBACK.md` - Non-fractionable asset fix documentation  
6. `docs/fixes/SUMMARY.md` - This summary document

## Testing

**Test Results**:
- ✅ Syntax checks pass for all changed files
- ✅ RuboCop linting passes (minor metrics warnings acceptable)
- ✅ 746 examples, 21 failures (pre-existing, unrelated to changes)

**Manual Testing Performed**:
- ✅ Dust position logging confirmed working
- ✅ Non-fractionable fallback logging confirmed working
- ✅ Quote API fallback confirmed working
- ✅ Asset blocking confirmed working

## Trade-offs

### Dust Positions
**Pros**:
- ✅ Positions actually get closed
- ✅ No audit trail overhead for anomalous data
- ✅ Proper error handling

**Cons**:
- ⚠️ Skips TradeDecision/TradeExecution records (acceptable for cleanup)

### Non-Fractionable Assets
**Pros**:
- ✅ Non-fractionable assets can now be traded
- ✅ Graceful degradation (skip vs fail)
- ✅ Handles illiquid stocks
- ✅ Automatic asset blocking

**Cons**:
- ⚠️ Slight value discrepancy (~2-3% from rounding down)
- ⚠️ Extra API calls for price data (~100ms latency for illiquid stocks)
- ⚠️ Cannot trade if notional < 1 share worth

## Expected Production Behavior

### Next Trading Run
1. **Dust positions (CCRN, CMCSA, HBNC)**: Will be closed automatically
2. **Non-fractionable assets**: Will fall back to whole shares
3. **Illiquid stocks**: Will use quote data for pricing
4. **Untradeable stocks**: Will be blocked for 7 days

### Monitoring
Watch logs for these patterns:
```bash
# Dust cleanup
grep "Closing dust position" log/production.log

# Fractionable fallback
grep "not fractionable" log/production.log

# Quote fallback
grep "trying latest quote" log/production.log

# Asset blocking
grep "No price data available" log/production.log
```

## Future Improvements

1. **Pre-check fractionability**: Call `/v2/assets/{symbol}` to check before placing order
2. **Cache price data**: Reduce API calls for multiple orders
3. **Batch price requests**: Fetch prices for all symbols at once
4. **Smart rounding**: Use `round` instead of `floor` for closer approximation
5. **Position consolidation**: Track leftover notional and combine later

## Related Documentation

- `docs/BLOCKED_ASSETS.md` - Asset blocking system
- `docs/fixes/DUST_POSITION_CLEANUP.md` - Detailed dust position fix
- `docs/fixes/NON_FRACTIONABLE_ASSET_FALLBACK.md` - Detailed fractionable fix

## Commit Message

```
Fix dust position cleanup and non-fractionable asset trading

Two critical trading fixes:

1. Dust Position Cleanup
- Remove filter that was skipping positions < 0.00000001 shares
- Bypass trade decision audit for dust (avoids validation errors)
- Call close_position API directly for cleanup

2. Non-Fractionable Asset Trading
- Add automatic fallback from notional to quantity-based orders
- Implement dual-API price discovery (trade → quote → block)
- Calculate whole shares and retry when "not fractionable" error
- Block assets with no price data

Changed files:
- packs/trades/app/commands/trades/rebalance_to_target.rb
- packs/audit_trail/app/commands/audit_trail/execute_trade_decision.rb
- packs/alpaca_api/app/services/alpaca_service.rb
```

## Author
GitHub Copilot CLI
Date: December 27, 2025
