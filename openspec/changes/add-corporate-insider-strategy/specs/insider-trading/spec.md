## ADDED Requirements

### Requirement: Corporate Insider Trade Data Fetching
The system SHALL fetch corporate insider trading data from the QuiverQuant API and persist it to the database with trader_source='insider'.

#### Scenario: Fetch insider purchases from API
- **WHEN** FetchInsiderTrades command is executed with default parameters
- **THEN** insider trades from the last 60 days are fetched from /beta/bulk/insidertrading endpoint
- **AND** trades are persisted with trader_source='insider'

#### Scenario: Parse insider-specific fields
- **WHEN** processing an insider trade from the API
- **THEN** the system extracts relationship (CEO, CFO, Director), shares_held, and percent_of_holdings
- **AND** stores trade_type (Form4, Form144, Form3)

#### Scenario: Deduplicate insider trades
- **WHEN** an insider trade already exists with same ticker + trader_name + transaction_date
- **THEN** the existing record is updated with latest data
- **AND** no duplicate record is created

#### Scenario: Handle API errors gracefully
- **WHEN** the QuiverQuant API returns 401 or 500 error
- **THEN** the command fails with clear error message
- **AND** no partial data is persisted

---

### Requirement: Insider Trade Filtering
The system SHALL filter insider trades to focus on high-signal purchases by corporate executives.

#### Scenario: Filter for purchases only
- **WHEN** generating insider mimicry portfolio
- **THEN** only Purchase transactions are included (sales excluded by default)

#### Scenario: Filter by relationship type
- **WHEN** configured to include only C-suite
- **THEN** only trades by CEO, CFO, COO are included
- **AND** trades by general directors are excluded

#### Scenario: Exclude scheduled trades
- **WHEN** a trade is marked as Form144 (scheduled sale)
- **THEN** it is excluded from portfolio generation
- **AND** only Form4 (discretionary) trades are used

#### Scenario: Minimum transaction size
- **WHEN** configured with minimum transaction value $50,000
- **THEN** trades below this threshold are filtered out

---

### Requirement: Insider Mimicry Portfolio Generation
The system SHALL generate target portfolios based on recent corporate insider purchases.

#### Scenario: Equal-weight allocation
- **WHEN** GenerateInsiderMimicryPortfolio is called with equal-weight mode
- **THEN** all qualifying stocks receive equal position sizes
- **AND** positions sum to 100% of allocated capital

#### Scenario: Role-weighted allocation
- **WHEN** using role-weighted mode
- **THEN** CEO trades receive 2.0x weight
- **AND** CFO trades receive 1.5x weight
- **AND** Director trades receive 1.0x weight
- **AND** weights are normalized to sum to 1.0

#### Scenario: Multiple insiders in same stock
- **WHEN** a CEO and CFO both buy the same stock
- **THEN** weights are summed (2.0 + 1.5 = 3.5)
- **AND** position size reflects combined conviction

#### Scenario: 30-day lookback window
- **WHEN** generating portfolio on January 31
- **THEN** only insider purchases from January 1-31 are included
- **AND** older trades are ignored

---

### Requirement: Strategy Configuration
The system SHALL support configurable parameters for the insider mimicry strategy.

#### Scenario: Configure relationship filters
- **WHEN** strategy is configured with allowed_relationships=['CEO', 'CFO']
- **THEN** only trades by CEOs and CFOs are included

#### Scenario: Configure lookback period
- **WHEN** strategy is configured with lookback_days=45
- **THEN** insider purchases from the last 45 days are included

#### Scenario: Configure position sizing mode
- **WHEN** strategy is configured with sizing_mode='role_weighted'
- **THEN** positions are weighted by role importance

#### Scenario: Include or exclude sales
- **WHEN** strategy is configured with include_sales=true
- **THEN** insider sales generate short positions
- **AND** purchases generate long positions

---

### Requirement: Multi-Strategy Execution
The system SHALL support running multiple strategies (congressional and insider) in parallel with configurable capital allocation.

#### Scenario: 50/50 split between strategies
- **WHEN** ExecuteMultiStrategyJob is configured with 50% congressional, 50% insider
- **THEN** $50k is allocated to congressional portfolio
- **AND** $50k is allocated to insider portfolio
- **AND** total portfolio equals $100k equity

#### Scenario: Generate separate portfolios
- **WHEN** executing multi-strategy
- **THEN** GenerateTargetPortfolio generates congressional positions
- **AND** GenerateInsiderMimicryPortfolio generates insider positions
- **AND** positions are combined before rebalancing

#### Scenario: Track per-strategy performance
- **WHEN** both strategies are active
- **THEN** performance metrics are tracked separately by strategy
- **AND** combined portfolio metrics are also calculated

---

### Requirement: Data Quality Validation
The system SHALL validate insider trade data quality and completeness.

#### Scenario: Validate relationship types
- **WHEN** processing insider trade
- **THEN** relationship must be one of: CEO, CFO, COO, Director, Officer, Other
- **AND** invalid relationships are logged as warnings

#### Scenario: Validate shares_held consistency
- **WHEN** an insider purchases shares
- **THEN** shares_held after transaction must be greater than shares purchased
- **AND** inconsistencies are flagged for review

#### Scenario: Detect missing critical fields
- **WHEN** an insider trade is missing transaction_date or ticker
- **THEN** the trade is skipped with error logged
- **AND** processing continues for remaining trades

---

### Requirement: Disclosure Lag Monitoring
The system SHALL monitor and report the disclosure lag between transaction dates and report dates for insider trades.

#### Scenario: Calculate average disclosure lag
- **WHEN** FetchInsiderTradesJob completes
- **THEN** average lag between transaction_date and disclosed_at is calculated
- **AND** logged as "Average disclosure lag: X days"

#### Scenario: Alert on stale data
- **WHEN** average disclosure lag exceeds 5 days
- **THEN** a warning is logged indicating possible data freshness issue

#### Scenario: Track disclosure lag by insider
- **WHEN** scoring insiders in future enhancement
- **THEN** historical disclosure lag can be factored into quality score

---

### Requirement: Backtest Validation
The system SHALL validate that the insider mimicry strategy delivers 5-7% annual alpha based on academic research.

#### Scenario: Run 2-year historical backtest
- **WHEN** backtesting insider strategy over 2023-2025
- **THEN** annual return is at least 5% above risk-free rate
- **AND** Sharpe ratio > 0.8
- **AND** max drawdown < 10%

#### Scenario: Compare to congressional strategy
- **WHEN** running parallel backtests
- **THEN** insider strategy shows lower disclosure lag (2 days vs 45 days)
- **AND** insider strategy may show higher turnover

#### Scenario: Validate diversification benefit
- **WHEN** running combined strategy backtest (50% congressional, 50% insider)
- **THEN** combined Sharpe ratio > max(congressional_sharpe, insider_sharpe)
- **AND** correlation between strategies < 0.5

---

### Requirement: Paper Trading Validation
The system SHALL validate insider strategy performance through 4 weeks of paper trading.

#### Scenario: Deploy to paper account
- **WHEN** insider strategy is deployed to paper trading
- **THEN** daily positions are generated from fresh insider data
- **AND** orders are executed via Alpaca paper account

#### Scenario: Monitor execution quality
- **WHEN** paper trading for 4 weeks
- **THEN** order fill rate is >95%
- **AND** slippage is within expected bounds (<0.1% per trade)

#### Scenario: Validate data pipeline reliability
- **WHEN** monitoring paper trading
- **THEN** FetchInsiderTradesJob succeeds 100% of daily runs
- **AND** no missing data blocks strategy execution

---

### Requirement: Production Deployment
The system SHALL support gradual rollout of insider strategy to production with monitoring and rollback capability.

#### Scenario: Initial allocation (Week 1)
- **WHEN** deploying to production
- **THEN** 10% of capital is allocated to insider strategy
- **AND** 90% remains in congressional strategy

#### Scenario: Gradual increase
- **WHEN** insider strategy performs as expected
- **THEN** allocation increases to 25% week 2, 50% week 4
- **AND** final allocation is 50% congressional, 50% insider by week 8

#### Scenario: Performance-based rollback
- **WHEN** insider strategy Sharpe ratio drops below 0.3 for 2 consecutive weeks
- **THEN** allocation is reduced back to previous level
- **AND** alert is sent for manual review
