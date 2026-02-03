# Quiver Quantitative Trader Account Upgrade

**Date**: December 10, 2025  
**Status**: Complete  
**Account**: api.quiverquant.com

---

## Upgrade Summary

The QuiverQuant account has been upgraded from **Hobbyist** to **Trader** tier, unlocking access to additional datasets and increased API capacity.

### Key Benefits

**1. Expanded Data Access**
- **Tier 1 Datasets** (Previously Available):
  - ✅ Congressional Trading (House & Senate)
  - ✅ WallStreetBets sentiment
  - ✅ Wikipedia pageviews
  - ✅ Twitter followers
  - ✅ App Store ratings

- **Tier 2 Datasets** (NOW AVAILABLE):
  - 🆕 **Corporate Insider Trading** - SEC Form 4 filings (2-day latency)
  - 🆕 **Government Contracts** - Federal procurement awards
  - 🆕 **Corporate Lobbying** - Lobbying Disclosure Act filings
  - 🆕 **Institutional Holdings** - Hedge fund 13F filings
  - 🆕 Additional sentiment/alternative datasets

**2. Increased API Capacity**
- **Rate Limits**: Up to 1,000 API calls per day (vs. 100/day Hobbyist)
- **Historical Data**: Full historical access for all datasets
- **Better Support**: Priority support and feature requests

---

## Strategic Impact

The Trader upgrade directly enables **4 priority strategies** from our roadmap:

### Immediately Available Strategies

#### 1. Corporate Insider Trading - Basic Mimicry 🟢 **READY TO IMPLEMENT**
- **Dataset**: `/beta/live/insiders`
- **Expected Alpha**: 5-7% annual (academic research)
- **Effort**: 3-4 weeks
- **Status**: Priority 2 in roadmap (see `docs/strategy/STRATEGY_ROADMAP.md` lines 73-108)

**Implementation Plan**:
```ruby
# New endpoint available
QuiverClient#fetch_insider_trades
  # Fields: Name, Relationship, Transaction, Shares, Value, Filed
  
# Reuse existing QuiverTrade model with trader_source: 'insider'
# New strategy: InsiderMimicryStrategy
```

#### 2. Corporate Insider - Consensus Detection 🟢 **AVAILABLE**
- **Dataset**: Same as above, requires analysis layer
- **Expected Alpha**: +2-4% over basic insider strategy
- **Effort**: 2-3 weeks (builds on #1)
- **Status**: Priority 3 in roadmap (lines 109-133)

#### 3. Government Contracts Strategy 🟡 **AVAILABLE (COMPLEX)**
- **Dataset**: `/beta/live/govcontracts` (all companies, last quarter)
- **Dataset**: `/beta/historical/govcontracts/{ticker}` (per ticker, quarterly history)
- **Expected Alpha**: Positive CAR on announcements
- **Effort**: 3-4 weeks
- **Status**: Backlog (lines 135-164)
- **Challenge**: Requires fundamental data (revenue) for materiality filter

#### 4. Corporate Lobbying Factor 🟢 **AVAILABLE**
- **Dataset**: `/beta/bulk/lobbying`
- **Expected Alpha**: 5.5-6.7% excess annual return
- **Effort**: 4-6 weeks
- **Status**: Backlog (lines 166-195)
- **Type**: Long-term factor (quarterly rebalancing)



---

## Recommended Implementation Priority

### Phase 1: Quick Wins (Q1 2026)

**1. Corporate Insider Trading - Basic** ⭐ **START HERE**
- **Why First**: 
  - Proven academic alpha (5-7% annual)
  - Low complexity (reuse existing infrastructure)
  - 2-day disclosure latency (better than congressional 45 days)
  - Natural extension of current congressional strategy
- **Timeline**: 3-4 weeks
- **Risk**: Low

### Phase 2: Enhanced Strategies (Q2 2026)

**2. Insider Consensus Detection**
- Enhances Strategy #1 with multi-insider agreement signals
- Timeline: 2-3 weeks

**3. Corporate Lobbying Factor**
- Long-term structural factor
- Quarterly rebalancing
- Timeline: 4-6 weeks

### Phase 3: Complex Strategies (Q3 2026)

**4. Government Contracts**
- Requires fundamental data integration
- Materiality filtering
- Timeline: 3-4 weeks + data sourcing

---

## Technical Implementation Requirements

### 1. Update QuiverClient Service

**Location**: `packs/data_fetching/app/services/quiver_client.rb`

**New Methods Needed**:
```ruby
class QuiverClient
  # Already exists
  def fetch_congressional_trades(options = {})
  
  # NEW: Add these methods
  def fetch_insider_trades(options = {})
    # Endpoint: /beta/live/insiders
    # Returns: Name, Relationship, Transaction, Shares, Value, Filed
  end
  
  def fetch_government_contracts(options = {})
    # Endpoint: /beta/live/govcontracts
    # Historical endpoint: /beta/historical/govcontracts/{ticker}
    # Returns: Date, Ticker, Agency, Amount
  end
  
  def fetch_lobbying_data(options = {})
    # Endpoint: /beta/bulk/lobbying
    # Returns: Date, Ticker, Amount, Client, Issues
  end
  
  def fetch_institutional_holdings(options = {})
    # Endpoint: /beta/bulk/institutional
    # Returns: Date, Ticker, Manager, Shares, Value
  end
end
```

### 2. Data Models

**Reuse Existing**:
- `QuiverTrade` model can handle insider trades with `trader_source: 'insider'`
- Add fields: `relationship`, `shares_held`, `percent_of_holdings`

**New Models Needed**:
- `GovernmentContract` (Date, Ticker, Agency, Amount)
- `LobbyingExpenditure` (Ticker, Quarter, Amount, Client, Issues)
- `MediaRecommendation` (Ticker, Personality, Show, Recommendation, Date)
- `InstitutionalHolding` (Ticker, Manager, Shares, Value, Date)

### 3. Strategy Classes

**New Strategy Commands** (in `packs/trading_strategies/`):
- `TradingStrategies::GenerateInsiderMimicryPortfolio`
- `TradingStrategies::GenerateInsiderConsensusPortfolio`
- `TradingStrategies::GenerateLobbyingFactorPortfolio`
- `TradingStrategies::GenerateContractsPortfolio`

### 4. Background Jobs

**New Jobs** (in `packs/data_fetching/`):
- `FetchInsiderTradesJob` (daily)
- `FetchGovernmentContractsJob` (daily)
- `FetchLobbyingDataJob` (quarterly)
- `FetchInstitutionalHoldingsJob` (quarterly)

### 5. Database Migrations

**For Insider Trading**:
```ruby
add_column :quiver_trades, :relationship, :string # CEO, CFO, Director
add_column :quiver_trades, :shares_held, :bigint
add_column :quiver_trades, :percent_of_holdings, :decimal
add_index :quiver_trades, [:trader_source, :transaction_date]
```

**New Tables**:
- `government_contracts`
- `lobbying_expenditures`
- `institutional_holdings`

---

## Testing Strategy

### 1. Data Integration Tests
- VCR cassettes for each new endpoint
- Handle API rate limits (1000/day)
- Error handling for Tier 2 access failures

### 2. Strategy Backtests
- Historical data validation (point-in-time)
- Walk-forward analysis
- Out-of-sample testing
- Transaction cost modeling

### 3. Paper Trading
- 4-8 week validation period per strategy
- Compare live vs. backtested performance
- Risk control validation

---

## Risk Management Updates

### New Risk Controls Needed

**1. Multi-Strategy Capital Allocation**:
- Per-strategy position limits
- Correlation monitoring between strategies
- Dynamic capital allocation based on performance
- Strategy-level kill switches

**2. Enhanced Position Sizing**:
- Relationship-based weighting (CEO > Director for insiders)
- Consensus multipliers (multiple insiders buying)
- Conviction scoring (signal strength)

---

## Documentation Updates Needed

### 1. Update Existing Docs

**README.md**:
- Add new strategy implementations section
- Update "Implemented Strategies" list

**STRATEGY_ROADMAP.md**:
- Mark strategies as "IN PROGRESS" or "COMPLETED"
- Update priorities based on Trader access

**DAILY_TRADING.md**:
- Multi-strategy execution workflow
- Capital allocation logic

### 2. Create New Docs

**docs/strategy/INSIDER_TRADING_STRATEGY.md**:
- Strategy logic and filters
- Backtesting methodology
- Expected performance

**docs/operations/MULTI_STRATEGY_EXECUTION.md**:
- Running multiple strategies simultaneously
- Capital allocation algorithm
- Performance monitoring

---

## Cost Analysis

### Quiver API Costs
- **Previous**: $10/month (Hobbyist)
- **Current**: ~$50-100/month (Trader - estimate, verify pricing)
- **Rate Limits**: 1000 calls/day (sufficient for 5+ strategies)

### Expected ROI
- **Conservative**: +5-10% annual alpha from new strategies
- **On $100k portfolio**: $5,000-10,000/year additional return
- **Net benefit**: $4,400-9,940/year (after data costs)

### Breakeven
- Need ~$1,000/month data cost to justify on $100k portfolio
- Current pricing well below breakeven threshold

---

## Next Actions

### Immediate (This Week)
1. ✅ Document upgrade impact (this file)
2. 🔲 Verify API access to Tier 2 endpoints (test calls)
3. 🔲 Update `.github/copilot-instructions.md` with new data sources
4. 🔲 Create GitHub issue: "Implement Corporate Insider Trading Strategy"

### Short Term (Next 2 Weeks)
1. 🔲 Extend `QuiverClient` with `fetch_insider_trades` method
2. 🔲 Add VCR tests for insider trading endpoint
3. 🔲 Enhance `QuiverTrade` model for insider data
4. 🔲 Create `InsiderMimicryStrategy` class
5. 🔲 Backtest insider strategy with historical data

### Medium Term (Next Month)
1. 🔲 Complete insider trading strategy implementation
2. 🔲 Paper trade insider strategy for 4 weeks
3. 🔲 Begin Inverse CNBC strategy development
4. 🔲 Design multi-strategy capital allocation framework

---

## Academic References

### Insider Trading Literature
- **"Generating Alpha from Insider Transactions"** - Positive abnormal returns on insider purchases
- **"Insider Trading: Does it increase Market Efficiency?"** - Alpha Architect study
- **Key Finding**: CEO/CFO purchases show highest signal strength

### Lobbying Literature
- **"Corporate Lobbying and Firm Performance"** - 5.5-6.7% excess annual return
- **"Determinants and Effects of Corporate Lobbying"** - $200 market value per $1 lobbying spend
- **Key Finding**: Lobbying intensity factor persists multi-year

---

## Conclusion

The Trader upgrade unlocks **immediate implementation** of 4 high-priority strategies from our roadmap, with expected combined alpha of **10-20% annually**. The enhanced API capacity (1000 calls/day) easily supports running multiple strategies in parallel.

**Recommended Path Forward**:
1. Start with **Corporate Insider Trading** (proven alpha, low complexity)
2. Build multi-strategy framework for concurrent execution
3. Gradually add consensus detection, lobbying, and government contracts strategies

The upgrade represents a **strategic inflection point** for the qq-system, transitioning from a single-strategy platform to a sophisticated **multi-strategy quantitative trading system**.

---

**Status**: ✅ Documented  
**Next**: Test API access to Tier 2 endpoints  
**Owner**: Development team  
**Timeline**: Q1-Q3 2026 implementation roadmap
