# Non-Fractionable Asset Fallback Fix

## Issue
Trading fails when trying to place notional (dollar-based) orders for non-fractionable assets:

```
Placing order: {symbol: "MAIA", side: "buy", notional: "96.1"}
Failed to place order: asset "MAIA" is not fractionable
Asset MAIA not fractionable, falling back to whole shares
Failed to get latest trade for MAIA: unexpected token 'Not' at line 1 column 1
❌ Trade failed: Cannot calculate whole shares
```

### Root Causes
1. **Fractionability**: Alpaca only allows notional orders for fractionable assets
2. **Missing Price Data**: Some illiquid stocks have no recent trades or quotes
3. **API Response Format**: Latest trade API returns "Not Found" text instead of JSON for some symbols

## Solution
**Automatic fallback with dual-API price discovery**:

1. Try notional order first
2. If "not fractionable":
   - Try latest_trade API
   - Fallback to latest_quote API (bid/ask midpoint)
   - Calculate whole shares: `floor(notional / price)`
   - Retry with `qty` parameter
3. If no price data available → block asset and skip

### Code Changes

#### File: `packs/alpaca_api/app/services/alpaca_service.rb`

**Added `latest_trade` with quote fallback**:
```ruby
def latest_trade(symbol)
  # Try latest trade first
  trade_data = get_latest_trade_data(symbol)
  return trade_data if trade_data
  
  # Fallback to latest quote
  Rails.logger.info("No trade data for #{symbol}, trying latest quote")
  get_latest_quote_data(symbol)
end

private

def get_latest_trade_data(symbol)
  # Calls /v2/stocks/{symbol}/trades/latest
  # Returns {price:, size:, timestamp:}
end

def get_latest_quote_data(symbol)
  # Calls /v2/stocks/{symbol}/quotes/latest
  # Returns {price: (bid+ask)/2, bid:, ask:, timestamp:}
end
```

#### File: `packs/audit_trail/app/commands/audit_trail/execute_trade_decision.rb`

**Enhanced `calculate_whole_shares`**:
```ruby
def calculate_whole_shares(symbol, notional_amount, side)
  alpaca_service = AlpacaService.new
  latest_trade = alpaca_service.latest_trade(symbol)
  price = latest_trade&.dig(:price)
  
  unless price&.positive?
    Rails.logger.warn("No price data for #{symbol} - will block asset")
    BlockedAsset.block_asset(symbol: symbol, reason: 'no_price_data')
    return nil
  end
  
  shares = (notional_amount.to_f / price).floor
  
  if shares.zero?
    Rails.logger.warn("Notional too small to buy 1 share of #{symbol}")
    return nil
  end
  
  Rails.logger.info("Calculated #{shares} shares at $#{price}")
  shares
end
```

## Expected Behavior

### Scenario 1: Non-fractionable with trade data
```
Placing order: {symbol: "MAIA", notional: "96.1"}
Asset MAIA not fractionable, falling back to whole shares
Calculated 3 whole shares for MAIA at $32.00 (notional: $96.1)
Placing order: {symbol: "MAIA", qty: "3"}
✅ Order placed successfully
```

### Scenario 2: Non-fractionable with only quote data
```
Placing order: {symbol: "HYPD", notional: "87.86"}
Asset HYPD not fractionable, falling back to whole shares
No trade data for HYPD, trying latest quote
Calculated 4 whole shares for HYPD at $21.50 (notional: $87.86)
Placing order: {symbol: "HYPD", qty: "4"}
✅ Order placed successfully
```

### Scenario 3: No price data available
```
Placing order: {symbol: "SWZ", notional: "87.78"}
Asset SWZ not fractionable, falling back to whole shares
No price data available for SWZ, cannot calculate whole shares - will block asset
⚠️ Asset blocked: no_price_data
❌ Trade skipped (asset will retry after 7 days)
```

## Price Discovery Strategy

The system tries multiple APIs in order:

1. **Latest Trade** (`/v2/stocks/{symbol}/trades/latest`)
   - Most accurate (actual executed price)
   - Only available if stock traded recently
   - Preferred for liquid stocks

2. **Latest Quote** (`/v2/stocks/{symbol}/quotes/latest`)
   - Bid/ask spread midpoint
   - Available even if no recent trades
   - Used for illiquid stocks

3. **Block Asset** (if both fail)
   - Marks symbol as untradeable
   - Auto-expires after 7 days
   - Prevents repeated failures

## Trade-offs

**Pros:**
- ✅ Non-fractionable assets can now be traded
- ✅ Handles illiquid stocks with quote fallback
- ✅ Blocks untradeable assets automatically
- ✅ Graceful degradation (skip vs fail)

**Cons:**
- ⚠️ Slight value discrepancy (rounds down to whole shares)
- ⚠️ Two API calls for illiquid stocks (~100ms latency)
- ⚠️ Quote midpoint may differ from execution price
- ⚠️ Notional amount too small → skipped entirely

### Value Discrepancy Examples

**Successful trade:**
- Target: $100, Price: $32.50, Shares: 3
- Actual: $97.50 (missing $2.50, ~2.5%)

**Skipped trade (too small):**
- Target: $50, Price: $60, Shares: 0
- Cannot buy even 1 share → skipped

## Blocked Asset Reasons

The system now blocks assets for these reasons:

1. `not_fractionable` - Can only trade whole shares
2. `no_price_data` - No trades or quotes available
3. `insufficient_buying_power` - Account lacks funds
4. `asset_not_active` - Delisted or halted

Blocked assets are retried after 7 days.

## Testing

Check logs for price discovery:
```bash
tail -f log/development.log | grep -E "not fractionable|whole shares|quote data"
```

Expected patterns:
- "Asset X not fractionable, falling back to whole shares"
- "Calculated 3 whole shares for X at $Y"
- "No trade data for X, trying latest quote"
- "No price data available for X - will block asset"

## Future Improvements

1. **Pre-check fractionability**: Call `/v2/assets/{symbol}` before placing order
2. **Cache price data**: Reduce API calls for multiple similar orders
3. **Smart rounding**: Use `round` instead of `floor` for closer approximation
4. **Batch price requests**: Fetch prices for all symbols at once

## Related Files
- `packs/audit_trail/app/commands/audit_trail/execute_trade_decision.rb` - Order execution with fallback
- `packs/alpaca_api/app/services/alpaca_service.rb` - Price discovery APIs
- `app/models/blocked_asset.rb` - Asset blocking system

## API Documentation
- Alpaca Latest Trade: https://alpaca.markets/docs/api-references/market-data-api/stock-pricing-data/historical/#latest-trade
- Alpaca Latest Quote: https://alpaca.markets/docs/api-references/market-data-api/stock-pricing-data/historical/#latest-quote
- Alpaca Fractionable Trading: https://alpaca.markets/docs/trading/orders/#fractional-trading
