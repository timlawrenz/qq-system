# QuiverQuant Trading Strategies Implementation Roadmap

**Last Updated**: November 10, 2025  
**Purpose**: Systematic roadmap for implementing individual trading strategies based on QuiverQuant alternative data

---

## Overview

This roadmap breaks down the strategic framework into discrete, implementable strategies. Each strategy is designed to exploit different market phenomena, providing portfolio diversification through uncorrelated alpha sources.

**Key Principle**: Build a multi-strategy platform running several approaches in parallel, rather than concentrating on a single strategy.

---

## Phase 1: Event-Driven Insider Strategies (FOUNDATION)

These strategies capitalize on discrete information releases from informed actors.

### 1.1 Congressional Trading - Simple Momentum ✅ **IMPLEMENTED**

**Status**: Live in production  
**Data Source**: QuiverQuant `/beta/bulk/congresstrading`  
**Holding Period**: 45-day rolling window  
**Current Performance**: 2.77% return, 3.1 win/loss ratio, -1.26 Sharpe

**Implementation Details**:
- Equal-weight portfolio of all stocks purchased by Congress members in last 45 days
- Uses transaction_date for signal generation
- Rebalances daily

**Next Steps**: 
- Monitor alpha decay
- Consider refinements (see 1.2-1.4 below)

---

### 1.2 Congressional Trading - Enhanced Filtering 🔄 **PRIORITY 1**

**Estimated Effort**: 2-3 weeks  
**Expected Impact**: +3-5% annual alpha over simple strategy  
**Risk Level**: Low (refinement of existing strategy)

**Implementation Requirements**:

1. **Data Enrichment**
   - Add `committee_assignment` field to QuiverTrade model
   - Fetch committee data from Quiver API or public sources
   - Map each trader to their committee(s)

2. **Filtering Logic**
   - Filter trades where politician's committee has oversight of company's industry
   - Weight trades by politician's historical track record
   - Identify consensus trades (multiple politicians buying same stock within short window)

3. **New Database Fields**
   ```ruby
   # Migration needed
   add_column :quiver_trades, :committees, :jsonb
   add_column :quiver_trades, :politician_id, :string
   add_index :quiver_trades, :politician_id
   ```

4. **New Models/Services**
   - `PoliticianProfile` model (track record, committees)
   - `CommitteeIndustryMapper` service
   - `ConsensusDetector` service

**Academic Support**: Studies show trades by politicians on relevant oversight committees generate higher returns.

---

### 1.3 Corporate Insider Trading - Basic Mimicry 🔄 **PRIORITY 2**

**Estimated Effort**: 3-4 weeks  
**Expected Impact**: 5-7% annual alpha (based on academic research)  
**Risk Level**: Low (proven strategy)

**Implementation Requirements**:

1. **Data Integration**
   - Add QuiverClient method: `fetch_insider_trades()`
   - API endpoint: `/beta/bulk/insidertrading`
   - Reuse existing `QuiverTrade` model with `trader_source: 'insider'`

2. **Strategy Variant**
   - Create `InsiderMimicryStrategy` class
   - Long on insider purchases, short on sales
   - 2-day disclosure window (faster than congressional)
   - Position sizing based on transaction value

3. **Database Enhancements**
   ```ruby
   # Add fields to quiver_trades
   add_column :quiver_trades, :relationship, :string # CEO, CFO, Director, etc.
   add_column :quiver_trades, :shares_held, :bigint
   add_column :quiver_trades, :percent_of_holdings, :decimal
   ```

4. **Key Filters**
   - Focus on purchases (higher signal)
   - Filter by relationship type (CEO/CFO higher priority)
   - Exclude automatic/scheduled trades

**Academic Support**: Insider purchases show statistically significant positive abnormal returns.

---

### 1.4 Corporate Insider Trading - Consensus Detection 🔄 **PRIORITY 3**

**Estimated Effort**: 2-3 weeks (builds on 1.3)  
**Expected Impact**: +2-4% alpha over basic insider strategy  
**Risk Level**: Medium (more complex logic)

**Implementation Requirements**:

1. **Consensus Logic**
   - Detect multiple insiders buying same stock within 30-day window
   - Calculate "insider conviction score" based on:
     - Number of insiders buying
     - Seniority of insiders
     - Size of purchases relative to holdings

2. **New Services**
   - `InsiderConsensusAnalyzer` service
   - `InsiderConvictionScorer` service

3. **Position Sizing**
   - Scale positions by conviction score
   - Higher allocation to consensus trades

**Academic Support**: Multiple insiders buying in concert is a stronger signal than individual trades.

---

### 1.5 Government Contracts Strategy 📋 **BACKLOG**

**Estimated Effort**: 3-4 weeks  
**Expected Impact**: Positive CAR on contract announcements  
**Risk Level**: Medium (materiality assessment needed)

**Implementation Requirements**:

1. **Data Integration**
   - Add QuiverClient method: `fetch_government_contracts()`
   - New model: `GovernmentContract`
   - Fields: contract_value, agency, award_date, ticker

2. **Strategy Logic**
   - Long position on contract award
   - Scale position by contract_value as % of company revenue
   - Time-based exit (5-10 days)

3. **Materiality Filter**
   - Only trade if contract > 1% of annual revenue
   - Requires integration with fundamental data (revenue)

4. **Data Requirements**
   - Company revenue data (Alpaca fundamental data or external source)
   - Contract modification tracking (complex)

**Academic Support**: Positive cumulative excess returns following contract announcements, especially in aerospace/defense.

---

### 1.6 Corporate Lobbying Factor 📋 **BACKLOG**

**Estimated Effort**: 4-6 weeks  
**Expected Impact**: 5.5-6.7% excess annual return  
**Risk Level**: Low (long-term factor)

**Implementation Requirements**:

1. **Data Integration**
   - Add QuiverClient method: `fetch_lobbying_data()`
   - New model: `LobbyingExpenditure`
   - Fields: ticker, quarter, amount, client, issues

2. **Factor Calculation**
   - Calculate "lobbying intensity" = total spend / market cap
   - Quarterly rebalancing
   - Requires fundamental data (market cap, assets)

3. **Strategy Type**
   - Market-neutral long/short
   - Long top quintile lobbying intensity
   - Short bottom quintile

4. **Portfolio Construction**
   - Define stock universe (e.g., Russell 3000)
   - Quintile ranking system
   - Rebalance quarterly

**Academic Support**: $200 market value per $1 lobbying spend. Strong multi-year persistence.

---

## Phase 2: Sentiment & Momentum Strategies (HIGH FREQUENCY)

These strategies exploit behavioral finance and crowd psychology.

### 2.1 WallStreetBets Momentum 📋 **BACKLOG**

**Estimated Effort**: 4-5 weeks  
**Expected Impact**: Significant abnormal returns (high volatility)  
**Risk Level**: High (requires sophisticated risk management)

**Implementation Requirements**:

1. **Data Integration**
   - Add QuiverClient method: `fetch_wsb_sentiment()`
   - Real-time/intraday updates required
   - New model: `SocialSentiment`
   - Fields: ticker, mentions, sentiment_score, timestamp

2. **Signal Generation**
   - Track sentiment momentum (1-hour MA crossing 24-hour MA)
   - Track mention volume spikes
   - Combine sentiment + volume thresholds

3. **Risk Management** (CRITICAL)
   - Tight trailing stop-losses (ATR-based)
   - Small position sizes (high volatility)
   - Maximum holding period (hours to days)
   - Daily loss limits

4. **Infrastructure Needs**
   - Real-time data processing
   - Faster execution engine
   - Sophisticated monitoring

**Academic Support**: WSB sentiment and activity have significant predictive power on weekly returns.

**Warning**: Highest risk strategy. Requires extensive testing and risk controls.

---

### 2.2 Inverse CNBC/Cramer (Contrarian) 📋 **BACKLOG**

**Estimated Effort**: 2-3 weeks  
**Expected Impact**: 26.3% CAGR, 1.17 Sharpe (per Quiver backtest)  
**Risk Level**: Medium (contrarian risk)

**Implementation Requirements**:

1. **Data Integration**
   - Add QuiverClient method: `fetch_cnbc_recommendations()`
   - New model: `MediaRecommendation`
   - Fields: ticker, personality, show, recommendation, date

2. **Strategy Logic**
   - Wait 1-2 days after "Buy" recommendation
   - Short the stock
   - Wait 1-2 days after "Sell" recommendation
   - Long the stock
   - Time-based exit (1-2 weeks)

3. **Personality Tracking**
   - Track by specific personalities (Cramer, etc.)
   - Historical performance by personality
   - Weight positions by historical accuracy (inverse)

4. **Risk Management**
   - Short squeeze monitoring
   - Borrow availability checks
   - Position size limits on shorts

**Academic Support**: Limited academic research, but strong empirical backtests from Quiver.

**Note**: This is a true contrarian strategy. Monitor for alpha decay as it becomes crowded.

---

## Phase 3: Multi-Factor Models (ADVANCED)

Sophisticated combinations of multiple data sources.

### 3.1 Political Connection Factor 📋 **BACKLOG**

**Estimated Effort**: 8-12 weeks  
**Expected Impact**: Theoretical (builds on proven components)  
**Risk Level**: High (model risk, overfitting)

**Implementation Requirements**:

1. **Composite Score Calculation**
   - Lobbying Intensity (normalized)
   - Congressional Buying Pressure (net purchases - sales)
   - Contract Dependency (contracts / revenue)
   - Combine with z-score normalization

2. **Data Dependencies**
   - Requires: Congressional trades (✅), Lobbying (❌), Contracts (❌)
   - Requires: Fundamental data (revenue, market cap)

3. **Portfolio Construction**
   - Define universe (Russell 3000)
   - Monthly/quarterly scoring
   - Long top quintile, short bottom quintile
   - Market-neutral

4. **New Models**
   - `PoliticalConnectionScore` model
   - `FactorRanking` model
   - `MarketNeutralPortfolio` service

5. **Backtesting Requirements**
   - Walk-forward analysis critical
   - Out-of-sample testing
   - Overfitting prevention

**Prerequisites**: Complete 1.2 (Congressional), 1.5 (Contracts), 1.6 (Lobbying) first.

**Warning**: Highest complexity. Significant overfitting risk. Requires rigorous validation.

---

## Phase 4: Consumer & Public Interest Data (EXPERIMENTAL)

Lower priority signals with uncertain alpha.

### 4.1 Wikipedia Pageviews Momentum 📋 **RESEARCH**

**Estimated Effort**: 2-3 weeks  
**Expected Impact**: Unknown (exploratory)  
**Risk Level**: Low (small positions)

**Implementation Requirements**:
- Fetch daily Wikipedia pageview counts
- Track rate of change in pageviews
- Correlation with price momentum?

**Status**: Research phase. Needs literature review and preliminary backtest.

---

### 4.2 Twitter Followers Growth 📋 **RESEARCH**

**Estimated Effort**: 2-3 weeks  
**Expected Impact**: Unknown (exploratory)  
**Risk Level**: Low

**Implementation Requirements**:
- Track corporate Twitter follower counts
- Measure growth rate
- Brand momentum proxy

**Status**: Research phase. Low priority.

---

### 4.3 App Store Ratings ("Hype Score") 📋 **RESEARCH**

**Estimated Effort**: 3-4 weeks  
**Expected Impact**: Unknown (exploratory)  
**Risk Level**: Low

**Implementation Requirements**:
- Scrape App Store reviews and ratings
- Calculate proprietary "hype score"
- Focus on consumer-facing tech companies

**Status**: Research phase. Low priority.

---

## Implementation Priorities

### Immediate (Next 3 Months)
1. **1.2 Congressional Trading - Enhanced Filtering** - Refine existing strategy
2. **1.3 Corporate Insider Trading - Basic** - Complete Strategy 1 from framework

### Short Term (3-6 Months)
3. **1.4 Corporate Insider - Consensus Detection** - Enhance insider strategy
4. **2.2 Inverse CNBC** - Low complexity, high backtested returns

### Medium Term (6-12 Months)
5. **1.5 Government Contracts** - Event-driven fundamental
6. **1.6 Corporate Lobbying** - Long-term factor
7. **2.1 WallStreetBets Momentum** - High-frequency (requires infrastructure)

### Long Term (12+ Months)
8. **3.1 Political Connection Factor** - Advanced multi-factor model
9. **Phase 4 Strategies** - Experimental/research

---

## Technical Architecture Implications

### Multi-Strategy Framework Required

The platform must support:
1. **Multiple concurrent strategies** running in parallel
2. **Capital allocation** between strategies
3. **Strategy-level performance tracking**
4. **Independent risk controls** per strategy

### Key Architectural Components

1. **Strategy Registry**
   ```ruby
   # packs/trading_strategies/app/models/strategy.rb
   class Strategy
     has_many :target_positions
     has_many :performance_metrics
     
     validates :name, :type, :status, presence: true
     
     scope :active, -> { where(status: 'active') }
   end
   ```

2. **Portfolio Allocator**
   - Allocate capital across strategies
   - Rebalancing logic
   - Risk budgeting

3. **Strategy Performance Monitor**
   - Track per-strategy metrics
   - Alpha decay detection
   - Automatic strategy deactivation on underperformance

---

## Risk Management Enhancements Needed

### Per-Strategy Controls
- Maximum position size per strategy
- Maximum loss per strategy
- Strategy-level stop-loss

### Portfolio-Level Controls
- Maximum correlation between strategies
- Overall leverage limits
- Aggregate drawdown limits

### Data Quality Controls
- Anomaly detection per dataset
- Data staleness alerts
- Provider uptime monitoring

---

## Success Metrics

### Strategy-Level KPIs
- Annual return
- Sharpe ratio
- Maximum drawdown
- Win/loss ratio
- Alpha decay rate

### Portfolio-Level KPIs
- Overall Sharpe ratio > 1.5
- Max drawdown < 15%
- Strategy correlation < 0.3
- Number of active strategies > 3

---

## Dependencies & Blockers

### Data Access
- ✅ Congressional Trading (Tier 1)
- ❌ Insider Trading (Tier 2?)
- ❌ Lobbying (Tier 2?)
- ❌ Government Contracts (Tier 2?)
- ❌ CNBC Recommendations (Tier 2?)
- ❌ WallStreetBets (Real-time tier?)

**Action Required**: Upgrade Quiver API subscription to access Tier 2 datasets.

### Fundamental Data
- Company revenue, market cap, assets needed for multiple strategies
- Options: Alpaca fundamental data, external provider (expensive)

### Infrastructure
- Real-time data processing (for WSB strategy)
- Faster execution engine (for high-frequency strategies)
- Enhanced monitoring and alerting

---

## Research & Validation Process

For each new strategy:

1. **Literature Review** (1 week)
   - Review academic papers
   - Analyze Quiver's methodology
   - Understand theoretical alpha source

2. **Data Exploration** (1-2 weeks)
   - Fetch sample data
   - Exploratory data analysis
   - Data quality assessment

3. **Backtest Development** (2-3 weeks)
   - Point-in-time data validation
   - Walk-forward analysis
   - Out-of-sample testing
   - Transaction cost modeling

4. **Paper Trading** (4-8 weeks)
   - Deploy to paper trading account
   - Monitor live performance
   - Compare to backtest expectations

5. **Production Deployment** (1 week)
   - Start with small capital allocation (5-10%)
   - Gradual ramp-up based on performance
   - Continuous monitoring

**Total per strategy**: 3-4 months from research to production

---

## Conclusion

This roadmap provides a systematic path to building a diversified, multi-strategy trading platform. The key is **incremental development** with rigorous validation at each step.

**Guiding Principles**:
1. Quality over quantity - thoroughly validate each strategy
2. Diversification - uncorrelated strategies reduce risk
3. Risk management - independent controls at every level
4. Continuous monitoring - detect alpha decay early
5. Iterative refinement - simple first, then enhance

**Next Steps**:
1. Review and approve roadmap
2. Prioritize first 2-3 strategies
3. Upgrade Quiver API subscription
4. Begin implementation of 1.2 (Enhanced Congressional)
