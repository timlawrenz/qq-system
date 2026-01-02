# QuiverQuant API Reference - Trader Tier

**Account Tier**: Trader  
**Base URL**: `https://api.quiverquant.com`  
**Rate Limit**: 1,000 calls/day  
**Authentication**: Bearer token in `Authorization` header

---

## Available Datasets

### Tier 1 Datasets (Originally Available)

#### 1. Congressional Trading
**Endpoint**: `/beta/bulk/congresstrading`  
**Update Frequency**: Daily (EOD)  
**Latency**: 1-45 days (STOCK Act requirement)  
**Historical Data**: January 2016 - Present  
**Coverage**: 1,800+ U.S. equities

**Response Fields**:
```json
{
  "Ticker": "NVDA",
  "Company": "NVIDIA Corporation",
  "Name": "Nancy Pelosi",
  "Transaction": "Purchase",
  "Trade_Size_USD": "$1,000,001 - $5,000,000",
  "Traded": "2023-11-22",
  "Filed": "2023-12-15T10:30:00Z"
}
```

**Client Method**: `QuiverClient#fetch_congressional_trades`

---

#### 2. WallStreetBets Sentiment
**Endpoint**: `/beta/historical/wallstreetbets/{ticker}`  
**Update Frequency**: Real-time/Intraday  
**Latency**: Near-zero  
**Historical Data**: August 2018 - Present  
**Coverage**: 6,000+ equities

**Response Fields**:
```json
{
  "Ticker": "GME",
  "Date": "2025-12-10",
  "Mentions": 1247,
  "Sentiment": 0.73,
  "Comments": 856
}
```

---

### Tier 2 Datasets (NOW AVAILABLE)

#### 3. Corporate Insider Trading ⭐ **PRIORITY 1**
**Endpoint**: `/beta/bulk/insidertrading`  
**Update Frequency**: Daily (EOD)  
**Latency**: 1-2 business days (SEC Form 4 requirement)  
**Historical Data**: January 2019 - Present  
**Coverage**: All SEC-registered companies

**Response Fields**:
```json
{
  "Ticker": "AAPL",
  "Name": "Tim Cook",
  "Relationship": "Chief Executive Officer",
  "Transaction": "Purchase",
  "Shares": 50000,
  "Value": 9250000,
  "Filed": "2025-12-09T16:45:00Z"
}
```

**Key Features**:
- CEO/CFO/Director classification
- Share count and dollar value
- Transaction type (Purchase/Sale/Option Exercise)
- Excludes 10b5-1 automatic plans (filtered)

**Strategy Use Cases**:
- Mimicking insider purchases (basic strategy)
- Consensus detection (multiple insiders buying)
- Relationship-weighted signals (CEO > Director)

**Client Method**: `QuiverClient#fetch_insider_trades` (TO BE IMPLEMENTED)

---

#### 4. Government Contracts
**Endpoints**:
- `/beta/live/govcontracts` (all companies, last quarter)
- `/beta/historical/govcontracts/{ticker}` (per ticker, quarterly history)

**Update Frequency**: Quarterly totals (refreshed frequently; Quiver live endpoint serves last quarter)

**Response Fields** (live + historical):
```json
{
  "Ticker": "LMT",
  "Amount": "35278845839.45",
  "Qtr": 4,
  "Year": 2025
}
```

**Notes / Limitations**:
- This dataset is **quarterly totals of obligations**, not individual award events.
- For now, our `GovernmentContract` ingestion stores these as `QuarterlyTotal` rows using quarter-end dates.
- Requires fundamental/company profile data (sector/industry, and ideally revenue) for materiality filtering.

**Strategy Use Cases**:
- Quarterly factor-style exposure to contract-heavy companies
- Materiality filter: contract totals > X% of annual revenue
- Sector focus: Aerospace, Defense, Tech

**Client Method**: `QuiverClient#fetch_government_contracts` (TO BE IMPLEMENTED)

---

#### 5. Corporate Lobbying ⭐ **LONG-TERM FACTOR**
**Endpoint**: `/beta/bulk/lobbying`  
**Update Frequency**: Daily (EOD)  
**Latency**: Up to 45 days post-quarter (Lobbying Disclosure Act)  
**Historical Data**: Varies (typically 2015+)  
**Coverage**: All public companies with lobbying activity

**Response Fields**:
```json
{
  "Ticker": "GOOGL",
  "Date": "2025-10-20",
  "Quarter": "Q3 2025",
  "Amount": 2800000,
  "Client": "Google LLC",
  "Issues": "Technology, Privacy, AI Regulation"
}
```

**Key Metrics**:
- Lobbying Intensity = Total Spend / Market Cap
- Quarterly rebalancing
- Long-term factor (multi-year persistence)

**Academic Support**:
- 5.5-6.7% excess annual return (top quintile lobbying intensity)
- $200 market value per $1 lobbying spend

**Strategy Use Cases**:
- Long/short factor (top vs. bottom quintile)
- Market-neutral portfolio
- Quarterly rebalancing

**Client Method**: `QuiverClient#fetch_lobbying_data` (TO BE IMPLEMENTED)

---

#### 6. CNBC Recommendations ⭐ **PRIORITY 2**
**Endpoint**: `/beta/bulk/cnbc`  
**Update Frequency**: Daily (EOD)  
**Latency**: Hours (same-day broadcast)  
**Historical Data**: December 2020 - Present  
**Coverage**: 1,500+ equities

**Response Fields**:
```json
{
  "Date": "2025-12-10",
  "Ticker": "TSLA",
  "Personality": "Jim Cramer",
  "Show": "Mad Money",
  "Recommendation": "Buy"
}
```

**Key Features**:
- Tracks specific personalities (Cramer, Najarian, etc.)
- Show attribution (Mad Money, Halftime Report, Fast Money)
- Historical track record per personality

**Strategy Use Cases**:
- **Contrarian**: Inverse Cramer (26.3% CAGR backtest)
- Short on "Buy" recommendations (after 1-2 day delay)
- Long on "Sell" recommendations (after 1-2 day delay)
- Time-based exit (1-2 weeks)

**Backtested Performance** (per Quiver):
- Inverse Cramer: 26.3% CAGR, 1.17 Sharpe
- Updated methodology (March 2023): 100% long + 100% short exposure

**Client Method**: `QuiverClient#fetch_cnbc_recommendations` (TO BE IMPLEMENTED)

---

#### 7. Institutional Holdings
**Endpoint**: `/beta/bulk/institutional`  
**Update Frequency**: Quarterly  
**Latency**: 45 days post-quarter (13F filing deadline)  
**Historical Data**: Varies (typically 2010+)  
**Coverage**: All 13F filers ($100M+ AUM)

**Response Fields**:
```json
{
  "Date": "2025-09-30",
  "Ticker": "AAPL",
  "Manager": "Berkshire Hathaway",
  "Shares": 915560382,
  "Value": 174250000000,
  "Change": "No Change"
}
```

**Strategy Use Cases**:
- Track "whale" activity (large institutional moves)
- Consensus detection (multiple institutions buying)
- Quality filter (institutional conviction)

**Client Method**: `QuiverClient#fetch_institutional_holdings` (TO BE IMPLEMENTED)

---

## API Usage Best Practices

### Rate Limiting
```ruby
# Built into QuiverClient
MAX_REQUESTS_PER_MINUTE = 60
REQUEST_INTERVAL = 1.0 second

# Daily limit: 1,000 calls
# Conservative approach: ~40 calls/hour = 960 calls/day
```

### Error Handling
```ruby
# HTTP Status Codes
200 => Success
401 => Authentication failed (check API key)
403 => Forbidden (check subscription tier)
422 => Invalid parameters
429 => Rate limit exceeded
500 => Server error
```

### Pagination
```ruby
# Use limit parameter for bulk endpoints
params = {
  limit: 100,        # Results per request
  start_date: Date.parse('2025-01-01'),
  end_date: Date.today
}
```

### Data Quality
```ruby
# Always validate incoming data
- Check for nil/blank values
- Validate date formats (ISO 8601)
- Handle ranged values (congressional trades)
- Filter out anomalies (e.g., 10b5-1 plans for insiders)
```

---

## Implementation Checklist

### Phase 1: Data Integration
- [ ] Extend `QuiverClient` with new methods
- [ ] Add VCR cassettes for Tier 2 endpoints
- [ ] Create new data models (contracts, lobbying, etc.)
- [ ] Database migrations for new tables
- [ ] Seed data for testing

### Phase 2: Strategy Development
- [ ] `InsiderMimicryStrategy`
- [ ] `InsiderConsensusStrategy`
- [ ] `InverseCNBCStrategy`
- [ ] `LobbyingFactorStrategy`
- [ ] `ContractsStrategy`

### Phase 3: Background Jobs
- [x] `FetchInsiderTradesJob`
- [ ] `FetchGovernmentContractsJob`
- [ ] `FetchLobbyingDataJob`
- [ ] `FetchCNBCRecommendationsJob`
- [ ] `FetchInstitutionalHoldingsJob`

### Phase 4: Testing & Validation
- [ ] Unit tests with mocked API responses
- [ ] Integration tests with VCR
- [ ] Backtesting with historical data
- [ ] Paper trading validation (4-8 weeks)

---

## Resources

### Documentation
- **Quiver API Docs**: https://api.quiverquant.com/docs/
- **Python SDK**: https://github.com/Quiver-Quantitative/python-api
- **Strategy Backtests**: https://www.quiverquant.com/strategies/

### Internal Documentation
- **Upgrade Overview**: `docs/operations/QUIVER_TRADER_UPGRADE.md`
- **Strategy Roadmap**: `docs/strategy/STRATEGY_ROADMAP.md`
- **Strategic Framework**: `docs/strategy/strategic-framework-with-alternative-data.md`

### Academic Literature
- Congressional Trading: "Trading Political Favors" (Impact of STOCK Act)
- Insider Trading: "Generating Alpha from Insider Transactions"
- Lobbying: "Corporate Lobbying and Firm Performance" (5.5-6.7% excess return)
- CNBC: Quiver's own backtests (26.3% CAGR Inverse Cramer)

---

**Status**: ✅ Documented  
**Last Updated**: December 10, 2025  
**Next**: Begin implementation of Corporate Insider Trading strategy
