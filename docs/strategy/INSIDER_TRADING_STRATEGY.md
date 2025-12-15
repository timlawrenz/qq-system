# Corporate Insider Trading Strategy - Basic Mimicry

**Status**: Initial Implementation Complete  
**Date**: December 11, 2025  
**Strategy Type**: Event-driven, Signal-following  
**Expected Alpha**: 5-7% annual (based on academic research)

---

## Strategy Overview

The Corporate Insider Trading Strategy mimics purchases made by corporate insiders (CEOs, CFOs, Directors) based on SEC Form 4 filings retrieved from QuiverQuant's `/beta/live/insiders` API endpoint.

### Key Principles

1. **Information Asymmetry**: Insiders have privileged knowledge about company prospects
2. **2-Day Disclosure Window**: Faster than congressional trading (45-day window)
3. **Purchase Signal Strength**: Insider purchases historically show positive abnormal returns
4. **Relationship-Based Filtering**: Focus on senior executives (CEO, CFO) with highest signal quality

---

## Implementation

### Operational Workflow

Insider data and maintenance tasks run via GLCommand commands and rake tasks, scheduled from cron on the local box:

- `FetchInsiderTrades` (GLCommand) loads recent insider trades into `quiver_trades`.
- `rake data_fetch:insider_daily` wraps `FetchInsiderTrades` for a daily 60-day lookback refresh.
- `Workflows::DailyMaintenanceChain` (GLCommand::Chainable) chains `FetchInsiderTrades` with blocked asset cleanup.
- `rake maintenance:daily` runs the chain once per trading day.

### Data Source

**API Endpoint**: `/beta/live/insiders` (QuiverQuant Trader tier)  
**Update Frequency**: Daily  
**Historical Depth**: Rolling 30-day window (configurable)

### Database Schema

Extended `quiver_trades` table with insider-specific fields:

```ruby
# New columns added by migration 20251211213258
add_column :quiver_trades, :relationship, :string        # "CEO", "CFO", "Director"
add_column :quiver_trades, :shares_held, :bigint         # Total shares held after transaction
add_column :quiver_trades, :ownership_percent, :decimal  # % ownership after transaction
```

### Strategy Command

**Class**: `TradingStrategies::GenerateInsiderMimicryPortfolio`  
**Location**: `packs/trading_strategies/app/commands/trading_strategies/generate_insider_mimicry_portfolio.rb`

**Configuration Options**:
- `lookback_days` (default: 30) - Days to look back for insider purchases
- `min_transaction_value` (default: $10,000) - Minimum purchase value to consider
- `executive_only` (default: true) - Filter for CEO/CFO/President titles only
- `position_size_weight_by_value` (default: true) - Legacy toggle for value-vs-count weighting (used when `sizing_mode` is nil)
- `sizing_mode` (optional) - `nil`/omit for legacy value-weighted, or `"equal_weight"` / `"role_weighted"` for explicit sizing modes
- `role_weights` (optional) - Hash of role weights, default: `{ "CEO" => 2.0, "CFO" => 1.5, "Director" => 1.0 }`

**Returns**:
- `target_positions` - Array of ticker allocations with target values
- `total_value` - Account equity
- `filters_applied` - Summary of active filters
- `stats` - Trade counts and ticker counts

---

## Strategy Logic

### 1. Data Retrieval

```ruby
QuiverTrade
  .where(transaction_type: 'Purchase')
  .where(trader_source: 'insider')
  .where(transaction_date: 30.days.ago..)
```

### 2. Filtering Pipeline

**Filter 1: Transaction Value**
- Exclude small "token" purchases under $10,000
- Focus on meaningful capital commitments

**Filter 2: Executive Titles** (if `executive_only: true`)
- CEO, CFO, President, Chief titles
- Higher signal quality from top executives

### 3. Position Weighting

Three effective weighting modes:

**Legacy Value-Weighted (default when `sizing_mode` is nil)**:
- Position size proportional to insider purchase value
- Larger purchases get larger allocations
- Assumes larger purchases indicate higher conviction

**Equal-Weighted** (`sizing_mode: "equal_weight"`):
- Each ticker gets equal allocation
- Simple diversification approach

**Role-Weighted** (`sizing_mode: "role_weighted"`):
- Each insider trade contributes a role weight (CEO, CFO, Director, etc.)
- Ticker weight is the sum of role weights across all trades in that ticker
- Default mapping: CEO=2.0, CFO=1.5, Director=1.0 (overridable via `role_weights`)
- Captures combined conviction from multiple high-signal insiders in the same stock

### 4. Portfolio Construction

- Normalize weights to 100% allocation
- Calculate target dollar values based on account equity
- Sort positions by allocation percentage (descending)

---

## Risk Management

### Diversification Warnings

- **No positions**: Logged warning if no trades pass filters
- **Under-diversified**: Warning if fewer than 5 positions generated

### Position Limits

Currently no hard position limits implemented. Future enhancements:
- Maximum position size (e.g., 20% per ticker)
- Minimum position count (e.g., require 5+ positions or fail)
- Sector concentration limits

---

## Academic Research Support

### Key Findings

1. **Insider Purchases Show Positive Abnormal Returns**
   - "Generating Alpha from Insider Transactions" - documented excess returns
   - Purchase signals stronger than sale signals

2. **CEO/CFO Trades Most Predictive**
   - "Insider Trading: Does it increase Market Efficiency?" - Alpha Architect
   - Senior executive trades show highest signal-to-noise ratio

3. **Recent Trades Strongest**
   - Signal decays over time
   - 30-day window balances freshness with sample size

---

## Usage Examples

### Basic Usage

```ruby
# Generate insider mimicry portfolio with defaults
result = TradingStrategies::GenerateInsiderMimicryPortfolio.call

result.target_positions
# => [
#   { ticker: 'AAPL', allocation_percent: 25.5, target_value: 25500.00 },
#   { ticker: 'MSFT', allocation_percent: 18.2, target_value: 18200.00 },
#   ...
# ]

result.stats
# => { total_trades: 45, trades_after_filters: 12, unique_tickers: 8 }
```

### Custom Configuration

```ruby
# More aggressive: include all insiders, 60-day window
result = TradingStrategies::GenerateInsiderMimicryPortfolio.call(
  lookback_days: 60,
  min_transaction_value: 5_000,
  executive_only: false
)

# Equal weight positions instead of value-weighted
result = TradingStrategies::GenerateInsiderMimicryPortfolio.call(
  position_size_weight_by_value: false
)
```

---

## Next Steps

### Immediate (Q1 2026)

1. **Fetch Insider Data Job**
   - Create `FetchInsiderTradesJob` background job
   - Schedule daily at market close
   - Handle API rate limits (1000/day)

2. **Integration Testing**
   - Test with live Quiver API data
   - Validate field mappings
   - Verify position calculations

3. **Paper Trading**
   - 4-8 week validation period
   - Compare live vs backtested performance
   - Monitor trade execution

### Phase 2 Enhancements (Q2 2026)

**Insider Consensus Detection** (Priority 3 strategy):
- Detect multiple insiders buying same stock
- Calculate conviction scores
- Boost position sizes for consensus trades
- Estimated +2-4% alpha improvement

**See**: `docs/strategy/STRATEGY_ROADMAP.md` lines 109-133

---

## Files Modified/Created

### New Files
- `packs/trading_strategies/app/commands/trading_strategies/generate_insider_mimicry_portfolio.rb`
- `db/migrate/20251211213258_add_insider_fields_to_quiver_trades.rb`
- `docs/strategy/INSIDER_TRADING_STRATEGY.md` (this file)

### Modified Files
- `packs/data_fetching/app/services/quiver_client.rb`
  - Added `fetch_insider_trades()` method
  - Added `parse_insider_trades_response()` helper
  - Added field parsing helpers (`parse_percent`, `parse_integer`, etc.)

### Database Changes
```sql
-- Migration 20251211213258
ALTER TABLE quiver_trades ADD COLUMN relationship VARCHAR;
ALTER TABLE quiver_trades ADD COLUMN shares_held BIGINT;
ALTER TABLE quiver_trades ADD COLUMN ownership_percent DECIMAL;
```

---

## Performance Monitoring

### Key Metrics to Track

1. **Trade Count Funnel**
   - Total insider purchases fetched
   - Trades passing value filter
   - Trades passing executive filter
   - Unique tickers in final portfolio

2. **Portfolio Characteristics**
   - Number of positions
   - Average position size
   - Largest position weight
   - Sector concentration

3. **Strategy Performance**
   - Daily/weekly returns
   - Sharpe ratio
   - Maximum drawdown
   - Correlation to market (SPY)

---

## References

### Academic Papers
- "Generating Alpha from Insider Transactions" - Positive abnormal returns on insider purchases
- "Insider Trading: Does it increase Market Efficiency?" - Alpha Architect study on CEO/CFO signal strength

### API Documentation
- QuiverQuant Insiders API: https://api.quiverquant.com/docs/#/operations/beta_live_insiders_retrieve

### Related Documents
- `docs/strategy/STRATEGY_ROADMAP.md` - Full strategy pipeline
- `docs/operations/QUIVER_TRADER_UPGRADE.md` - Tier 2 access details
- `packs/trading_strategies/app/commands/trading_strategies/generate_enhanced_congressional_portfolio.rb` - Similar strategy pattern

---

**Status**: ✅ Core Implementation Complete  
**Next**: Create FetchInsiderTradesJob and test with live API  
**Timeline**: 2-3 weeks to production-ready
