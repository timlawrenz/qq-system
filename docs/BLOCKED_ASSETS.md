# Blocked Assets System

## Overview

The Blocked Assets system automatically tracks and filters out untradeable assets during portfolio rebalancing. This prevents repeated trade failures and improves system reliability when dealing with inactive, delisted, or non-fractionable securities.

## How It Works

### Automatic Blocking

When a rebalancing operation encounters an asset that cannot be traded (e.g., "asset PRO is not active"), the system automatically:

1. **Records the failure** in the `blocked_assets` table
2. **Skips the order** instead of failing the entire rebalancing operation
3. **Continues processing** remaining positions
4. **Filters the asset** from future portfolio generations

### Expiration & Auto-Cleanup

- **Blocked assets expire after 7 days** to allow retry if they become tradable again
- **Automatic cleanup** removes expired blocks
- **Manual override** available via Rake tasks

## Database Schema

```ruby
create_table :blocked_assets do |t|
  t.string :symbol, null: false          # e.g., 'PRO', 'AAPL'
  t.string :reason, null: false          # e.g., 'asset_not_active'
  t.datetime :blocked_at, null: false    # When first blocked
  t.datetime :expires_at, null: false    # When block expires (7 days)
  t.timestamps
end

add_index :blocked_assets, :symbol, unique: true
add_index :blocked_assets, :expires_at
```

## Model Methods

### Class Methods

```ruby
# Get list of all currently blocked symbols
BlockedAsset.blocked_symbols
# => ['PRO', 'DELISTED']

# Block a new asset (or update expiration if already blocked)
BlockedAsset.block_asset(symbol: 'PRO', reason: 'asset_not_active')

# Clean up expired blocks
BlockedAsset.cleanup_expired
# => 5 (number of records deleted)
```

### Instance Methods

```ruby
asset = BlockedAsset.first

# Check if expired
asset.expired?
# => false

# Days until expiration
asset.days_until_expiration
# => 5
```

### Scopes

```ruby
# Active (non-expired) blocks
BlockedAsset.active

# Expired blocks (ready for cleanup)
BlockedAsset.expired
```

## Integration Points

### 1. RebalanceToTarget Command

Automatically blocks assets when order placement fails:

```ruby
# In packs/trades/app/commands/trades/rebalance_to_target.rb

rescue StandardError => e
  if /asset .+ is not active|not tradable|not fractionable/i.match?(e.message)
    BlockedAsset.block_asset(symbol: position[:symbol], reason: 'asset_not_active')
    # ... skip order and continue
  end
end
```

### 2. Portfolio Generation Commands

Filters blocked assets from target portfolios:

```ruby
# In packs/trading_strategies/app/commands/trading_strategies/generate_target_portfolio.rb

def fetch_unique_purchase_tickers(date: Time.current)
  tickers = QuiverTrade.purchases.recent(45, date: date).pluck(:ticker).uniq
  
  blocked_symbols = BlockedAsset.blocked_symbols
  tickers - blocked_symbols  # Remove blocked assets
end
```

### 3. Blended Portfolio Builder

Final safety check before rebalancing:

```ruby
# In packs/trading_strategies/app/services/blended_portfolio_builder.rb

def apply_risk_controls(positions)
  blocked_symbols = BlockedAsset.blocked_symbols
  if blocked_symbols.any?
    positions = positions.reject { |p| blocked_symbols.include?(p.symbol) }
  end
  # ... continue with other controls
end
```

## Management Tasks

### List Blocked Assets

```bash
bundle exec rake blocked_assets:list
```

**Output:**
```
Currently blocked assets (3):

  PRO        | Reason: asset_not_active  | Expires in 5 day(s)
  DELISTED   | Reason: asset_not_active  | Expires in 2 day(s)
  SPAC-OLD   | Reason: asset_not_active  | Expires in 1 day(s)
```

### Clean Up Expired Assets

```bash
bundle exec rake blocked_assets:cleanup
```

**Output:**
```
Cleaning up expired blocked assets...
✓ Removed 2 expired blocked asset(s)
```

### Manually Unblock an Asset

```bash
bundle exec rake blocked_assets:unblock[PRO]
```

**Output:**
```
✓ Unblocked PRO
```

## Monitoring & Logs

### Rebalancing Logs

When an asset is blocked during rebalancing:

```
Skipped buy order for PRO ($513.61): asset not active or not tradable
```

### Portfolio Generation Logs

When blocked assets are filtered:

```
Filtered 3 blocked assets from target portfolio
```

### Blended Portfolio Logs

When blocked assets are removed during risk controls:

```
BlendedPortfolioBuilder: Filtered 2 blocked assets from final portfolio
```

## Testing

### Model Tests

```bash
bundle exec rspec spec/models/blocked_asset_spec.rb
```

**Coverage:**
- ✓ Validations (presence, uniqueness)
- ✓ Scopes (active, expired)
- ✓ Class methods (block_asset, cleanup_expired, blocked_symbols)
- ✓ Instance methods (expired?, days_until_expiration)

### Integration Tests

```bash
bundle exec rspec packs/trades/spec/commands/trades/rebalance_to_target_spec.rb
```

**Coverage:**
- ✓ Rebalancing continues when asset is inactive
- ✓ Blocked asset is recorded in database
- ✓ Other orders execute successfully

## Common Scenarios

### Scenario 1: Asset Becomes Delisted

1. **Rebalancing fails** with "asset XYZ is not active"
2. **System automatically blocks** XYZ for 7 days
3. **Future portfolios** exclude XYZ
4. **After 7 days**, block expires and system retries

### Scenario 2: Asset Symbol Changes

1. **Old symbol** blocked automatically (e.g., "TWTR")
2. **New symbol** begins appearing in data (e.g., "X")
3. **Old symbol** expires after 7 days
4. **System adapts** to new symbol naturally

### Scenario 3: Temporary Trading Halt

1. **Asset blocked** during trading halt
2. **7-day expiration** allows automatic retry
3. **If still halted**, re-blocked automatically
4. **Once tradable**, system resumes normal operations

## Best Practices

### 1. Regular Cleanup

Run cleanup weekly to remove expired blocks:

```bash
# Add to crontab or scheduled job
0 0 * * 0 cd /path/to/qq-system && bundle exec rake blocked_assets:cleanup
```

### 2. Monitor Block Frequency

High block rates may indicate data quality issues:

```ruby
# Check block rate
total_tickers = QuiverTrade.distinct.count(:ticker)
blocked_count = BlockedAsset.active.count
block_rate = (blocked_count.to_f / total_tickers * 100).round(2)

puts "Block rate: #{block_rate}%"
# Ideal: < 5%
# Warning: > 10%
# Critical: > 20%
```

### 3. Manual Review

Periodically review blocked assets:

```bash
bundle exec rake blocked_assets:list
```

Check if blocks are legitimate or indicate data issues.

### 4. Testing with Blocked Assets

```ruby
# In tests, create blocked assets for specific scenarios
before do
  BlockedAsset.block_asset(symbol: 'INVALID', reason: 'test')
end

it 'excludes blocked assets from portfolio' do
  result = GenerateTargetPortfolio.call(total_equity: 10_000)
  expect(result.target_positions.map(&:symbol)).not_to include('INVALID')
end
```

## Performance Considerations

### Database Queries

- **Index on `symbol`** ensures O(1) lookups
- **Index on `expires_at`** optimizes cleanup queries
- **Unique constraint** prevents duplicates

### Caching

Consider caching blocked symbols list if checked frequently:

```ruby
Rails.cache.fetch('blocked_symbols', expires_in: 5.minutes) do
  BlockedAsset.blocked_symbols
end
```

## Troubleshooting

### Asset Not Being Blocked

**Check logs** for error message pattern:
```ruby
# Must match this pattern:
/asset .+ is not active|not tradable|not fractionable/i
```

### Asset Stuck in Blocked State

**Manually unblock**:
```bash
bundle exec rake blocked_assets:unblock[SYMBOL]
```

### Too Many Assets Blocked

**Investigate root cause**:
1. Check Alpaca API status
2. Verify data source quality
3. Review recent symbol changes
4. Check market conditions (halts, etc.)

## Future Enhancements

### Potential Improvements

1. **Block reason categories** (delisted, halted, non-fractionable)
2. **Variable expiration times** by reason
3. **Notification system** for manual review
4. **Historical block tracking** for analysis
5. **Auto-unblock on successful trade** (verify asset is tradable)

## Related Documentation

- [Multi-Strategy Trading System](./MULTI_STRATEGY_SYSTEM.md)
- [Rebalancing Process](./REBALANCING.md)
- [Data Models](./DATA_MODELS.md)
