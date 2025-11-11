## ADDED Requirements

### Requirement: Company-Level Insider Consensus Detection
The system SHALL detect when multiple insiders from the same company purchase stock within a 30-day rolling window.

#### Scenario: Two insiders from same company buy within window
- **WHEN** the CEO of ACME Corp buys on January 5
- **AND** the CFO of ACME Corp buys on January 20
- **THEN** ACME Corp is flagged as having insider consensus (count=2)

#### Scenario: Purchases outside consensus window
- **WHEN** the CEO buys on January 1
- **AND** the CFO buys on February 15 (45 days later)
- **THEN** no consensus is detected (outside 30-day window)

#### Scenario: Three insiders create strong consensus
- **WHEN** three insiders (CEO, CFO, COO) all buy within 30 days
- **THEN** consensus count = 3
- **AND** this triggers maximum consensus boost

#### Scenario: Filter by transaction type
- **WHEN** detecting consensus
- **THEN** only Purchase transactions are considered (sales excluded)

---

### Requirement: Insider Conviction Score Calculation
The system SHALL calculate conviction scores (0-10 scale) based on the strength of insider consensus signals.

#### Scenario: Calculate score for two C-suite insiders
- **WHEN** a CEO (weight=3.0) and CFO (weight=2.0) both buy
- **THEN** base conviction score = 5.0 (3.0 + 2.0)
- **AND** normalized to 0-10 scale

#### Scenario: Weight by transaction size
- **WHEN** a CEO buys 10% of their holdings (large purchase)
- **THEN** conviction score receives 1.5x size multiplier
- **AND** final score = base * size_multiplier

#### Scenario: Combine multiple factors
- **WHEN** calculating conviction score
- **THEN** score = (insider_count × seniority_weight × size_weight)
- **AND** capped at maximum 10.0

#### Scenario: Low conviction scenario
- **WHEN** only one junior director buys (weight=1.0, small size)
- **THEN** conviction score ≈ 2.0 (low conviction)

---

### Requirement: Behavioral Shift Detection
The system SHALL identify significant behavioral changes by corporate insiders that indicate unusually high conviction.

#### Scenario: CEO's first-ever open market purchase
- **WHEN** a CEO makes their first open-market stock purchase
- **AND** they have been CEO for 2+ years with no prior purchases
- **THEN** first_purchase_flag is set to true
- **AND** this triggers a 1.2x conviction multiplier

#### Scenario: Sudden increase in purchase frequency
- **WHEN** an insider typically buys once per year
- **AND** suddenly makes 3 purchases in 30 days
- **THEN** behavioral shift is flagged
- **AND** conviction score is boosted

#### Scenario: Insider buying after long silence
- **WHEN** an insider hasn't bought in 3+ years
- **AND** makes a large purchase
- **THEN** marked as high-conviction signal

---

### Requirement: Cross-Company Stock Clustering Detection
The system SHALL detect when insiders from multiple unrelated companies all buy the same stock.

#### Scenario: Three companies' insiders buy same stock
- **WHEN** insiders from ACME Corp, BETA Inc, and GAMMA LLC all buy NVDA
- **AND** all purchases occur within 30 days
- **THEN** NVDA is flagged as cross-company consensus
- **AND** conviction score reflects multiple independent signals

#### Scenario: Filter for unrelated companies
- **WHEN** detecting cross-company clustering
- **THEN** only include companies from different industries
- **AND** exclude sister companies (same parent)

---

### Requirement: Consensus-Based Position Sizing
The system SHALL increase position sizes for stocks with strong insider consensus signals.

#### Scenario: Two-insider consensus multiplier
- **WHEN** a stock has consensus from 2 insiders
- **THEN** position weight is multiplied by 1.5x

#### Scenario: Three-or-more insider consensus
- **WHEN** a stock has consensus from 3+ insiders
- **THEN** position weight is multiplied by 2.0x

#### Scenario: First-purchase bonus
- **WHEN** consensus includes a CEO's first-ever purchase
- **THEN** an additional 1.2x multiplier is applied
- **AND** final weight = base × consensus_multiplier × first_purchase_multiplier

#### Scenario: Combined with role weighting
- **WHEN** calculating final position size
- **THEN** weight = role_weight × consensus_multiplier
- **AND** all weights normalized to sum to 1.0

---

### Requirement: Consensus Configuration
The system SHALL support configurable parameters for consensus detection and weighting.

#### Scenario: Configure consensus window
- **WHEN** strategy is configured with consensus_window_days=45
- **THEN** insiders purchasing within 45 days are grouped

#### Scenario: Configure minimum insiders threshold
- **WHEN** strategy is configured with min_insiders_for_consensus=3
- **THEN** only stocks with 3+ insiders receive consensus boost

#### Scenario: Configure consensus multiplier
- **WHEN** strategy is configured with consensus_multiplier=1.8
- **THEN** consensus stocks receive 1.8x position weight

#### Scenario: Disable consensus boost
- **WHEN** strategy is configured with consensus_boost=false
- **THEN** all stocks receive equal weight (role-weighted only)

---

### Requirement: Consensus Metrics Persistence
The system SHALL persist calculated consensus metrics to the database for performance and auditability.

#### Scenario: Store consensus count
- **WHEN** CalculateInsiderConsensusJob runs
- **THEN** insider_consensus_count is updated for each trade
- **AND** reflects number of insiders buying same company stock

#### Scenario: Store conviction score
- **WHEN** calculating conviction scores
- **THEN** insider_conviction_score (0-10) is persisted
- **AND** can be queried for portfolio generation

#### Scenario: Track consensus window
- **WHEN** storing consensus metrics
- **THEN** consensus_window_start date is recorded
- **AND** enables historical analysis of consensus patterns

---

### Requirement: Daily Consensus Calculation
The system SHALL automatically calculate and update consensus metrics daily after fetching new insider trades.

#### Scenario: Job chaining
- **WHEN** FetchInsiderTradesJob completes successfully
- **THEN** CalculateInsiderConsensusJob is triggered
- **AND** consensus metrics are recalculated for recent trades

#### Scenario: Incremental updates
- **WHEN** calculating consensus
- **THEN** only trades from the last 60 days are processed
- **AND** older consensus metrics remain unchanged

#### Scenario: Handle errors gracefully
- **WHEN** consensus calculation fails for a trade
- **THEN** error is logged with trade details
- **AND** processing continues for remaining trades

---

### Requirement: Backtest Validation
The system SHALL validate that consensus enhancement delivers +2-4% annual alpha over basic insider strategy.

#### Scenario: Compare basic vs consensus-enhanced
- **WHEN** backtesting over 2-year period
- **THEN** consensus-enhanced Sharpe ratio > basic Sharpe ratio
- **AND** annual return improvement is 2-4%
- **AND** max drawdown remains comparable

#### Scenario: Validate optimal parameters
- **WHEN** testing different consensus windows (15, 30, 45 days)
- **THEN** 30-day window shows best risk-adjusted returns
- **AND** this becomes the default parameter

#### Scenario: Test consensus multiplier effectiveness
- **WHEN** comparing 1.3x, 1.5x, 2.0x multipliers
- **THEN** 1.5x multiplier provides optimal Sharpe ratio
- **AND** higher multipliers increase drawdown without proportional return increase

---

### Requirement: False Positive Prevention
The system SHALL implement safeguards to prevent false positives from random clustering.

#### Scenario: Minimum purchase value filter
- **WHEN** detecting consensus
- **THEN** only purchases > $50,000 are considered
- **AND** small trades are excluded (likely noise)

#### Scenario: Statistical significance check
- **WHEN** detecting cross-company clustering
- **THEN** verify clustering is statistically significant vs baseline rate
- **AND** flag suspicious patterns for review

#### Scenario: Maximum consensus dilution
- **WHEN** a stock has 10+ insiders buying (unusual)
- **THEN** cap consensus multiplier at 2.0x (prevent over-concentration)

---

### Requirement: Monitoring and Alerting
The system SHALL monitor consensus detection patterns and alert on anomalies.

#### Scenario: Track consensus rate
- **WHEN** CalculateInsiderConsensusJob completes
- **THEN** log percentage of trades with consensus (expected: 10-20%)
- **AND** alert if consensus rate drops below 5% or exceeds 40%

#### Scenario: Alert on conviction score distribution
- **WHEN** monitoring conviction scores
- **THEN** expected distribution: mean ≈ 5.0, std dev ≈ 2.0
- **AND** alert if distribution shifts significantly

#### Scenario: Monitor first-purchase flags
- **WHEN** tracking behavioral shifts
- **THEN** first-purchase rate should be <5% of all trades
- **AND** alert if rate exceeds 10% (possible data quality issue)
