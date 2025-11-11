## ADDED Requirements

### Requirement: Committee-Based Trade Filtering
The system SHALL filter congressional trades to only include transactions where the politician's committee assignment has oversight jurisdiction over the company's industry sector.

#### Scenario: Energy Committee member trading energy stock
- **WHEN** a politician on the Energy Committee buys an energy sector stock
- **THEN** the trade is included in the portfolio generation

#### Scenario: Politician trading outside committee jurisdiction
- **WHEN** a politician on the Agriculture Committee buys a technology stock
- **THEN** the trade is excluded from portfolio generation

#### Scenario: Politician with no committee data
- **WHEN** a politician has no committee assignments mapped in the database
- **THEN** the trade is included (default to not filtering unknown data)

---

### Requirement: Politician Quality Scoring
The system SHALL assign quality scores (0-10 scale) to politicians based on their historical trading performance over a trailing 12-month period.

#### Scenario: Calculate quality score for high-performing politician
- **WHEN** a politician has 80% win rate and 15% average return over 12 months
- **THEN** the quality score is calculated as approximately 9.0

#### Scenario: Calculate quality score for average politician
- **WHEN** a politician has 50% win rate and 5% average return
- **THEN** the quality score is calculated as approximately 5.0

#### Scenario: Politician with insufficient trade history
- **WHEN** a politician has fewer than 5 trades in the last 12 months
- **THEN** the quality score defaults to 5.0 (neutral)

#### Scenario: Monthly score recalculation
- **WHEN** the ScorePoliticiansJob runs on the 1st of each month
- **THEN** all politician quality scores are recalculated using latest 12-month data

---

### Requirement: Consensus Trade Detection
The system SHALL identify consensus trades when 2 or more politicians purchase the same stock within a 30-day rolling window.

#### Scenario: Two politicians buy same stock within window
- **WHEN** Politician A buys NVDA on January 1
- **AND** Politician B buys NVDA on January 15
- **THEN** NVDA is flagged as a consensus trade

#### Scenario: Multiple purchases outside time window
- **WHEN** Politician A buys NVDA on January 1
- **AND** Politician B buys NVDA on February 15 (45 days later)
- **THEN** NVDA is NOT flagged as a consensus trade

#### Scenario: Three high-quality politicians create strong consensus
- **WHEN** three politicians with quality scores >8.0 all buy the same stock within 30 days
- **THEN** the consensus strength score is calculated as sum of quality scores (>24.0)

---

### Requirement: Dynamic Position Sizing
The system SHALL calculate position sizes based on signal strength, incorporating quality scores and consensus detection.

#### Scenario: High-quality politician trade
- **WHEN** a politician with quality score 9.0 makes a purchase
- **THEN** the position weight is multiplied by 1.8 (9.0 / 5.0 quality multiplier)

#### Scenario: Consensus trade bonus
- **WHEN** a stock is flagged as a consensus trade (2+ politicians)
- **THEN** the position weight is multiplied by 1.5 (consensus multiplier)

#### Scenario: Combined quality and consensus
- **WHEN** a consensus trade involves politicians with average quality score 8.0
- **THEN** the position weight is multiplied by 2.4 (1.6 quality × 1.5 consensus)

#### Scenario: Normalization across portfolio
- **WHEN** multiple stocks have different signal strengths
- **THEN** all weights are normalized to sum to 1.0 before calculating dollar allocations

---

### Requirement: Politician Profile Management
The system SHALL maintain profiles for each politician including committee memberships, historical performance metrics, and quality scores.

#### Scenario: Create new politician profile
- **WHEN** a new congressional trader is detected in QuiverTrade data
- **THEN** a PoliticianProfile record is created with default quality score 5.0

#### Scenario: Update committee memberships quarterly
- **WHEN** the RefreshCommitteeDataJob runs
- **THEN** committee membership data is fetched from ProPublica Congress API
- **AND** CommitteeMembership records are created or updated

#### Scenario: Track politician performance metrics
- **WHEN** a politician's quality score is calculated
- **THEN** the profile stores total_trades, winning_trades, average_return, and last_scored_at

---

### Requirement: Committee-Industry Mapping
The system SHALL maintain mappings between congressional committees and industry sectors they oversee.

#### Scenario: Map House Energy & Commerce to multiple industries
- **WHEN** seeding committee-industry mappings
- **THEN** House Energy & Commerce (HSIF) maps to Healthcare, Technology, and Energy industries

#### Scenario: Stock classification to industry
- **WHEN** classifying "NVDA" (NVIDIA)
- **THEN** it is mapped to Technology and Semiconductors industries

#### Scenario: Committee jurisdiction check
- **WHEN** checking if House Armed Services has jurisdiction over a defense contractor
- **THEN** the system confirms overlap between committee's industries (Defense, Aerospace) and stock's industries

---

### Requirement: Enhanced Strategy Configuration
The system SHALL support configurable filters for the enhanced congressional strategy including committee filtering, minimum quality scores, consensus detection, and position sizing parameters.

#### Scenario: Enable all filters with default settings
- **WHEN** GenerateEnhancedCongressionalPortfolio is called with default filters
- **THEN** committee_filter=true, min_quality_score=5.0, consensus_boost=true, min_politicians_for_consensus=2

#### Scenario: Disable committee filtering
- **WHEN** filters are configured with committee_filter=false
- **THEN** trades are not filtered by committee jurisdiction

#### Scenario: Raise minimum quality threshold
- **WHEN** filters are configured with min_quality_score=7.0
- **THEN** only trades from politicians with quality scores ≥7.0 are included

#### Scenario: Minimum portfolio size safety check
- **WHEN** filters reduce portfolio to fewer than 3 stocks
- **THEN** the system logs a warning and progressively relaxes filters

---

### Requirement: Data Quality Monitoring
The system SHALL validate committee data completeness and log warnings when filtering reduces portfolio size below minimum thresholds.

#### Scenario: High committee coverage
- **WHEN** checking committee data coverage
- **THEN** at least 80% of active politicians have committee assignments mapped

#### Scenario: Portfolio size too small
- **WHEN** filters reduce the target portfolio to fewer than 5 stocks
- **THEN** a warning is logged indicating insufficient diversification

#### Scenario: Stale committee data
- **WHEN** committee data has not been refreshed in over 6 months
- **THEN** a warning is logged prompting manual refresh

---

### Requirement: Backtest Validation
The system SHALL validate that the enhanced strategy delivers at least +3% annual alpha improvement over the simple baseline strategy.

#### Scenario: Run comparative backtest
- **WHEN** backtesting both simple and enhanced strategies over same 2-year period
- **THEN** enhanced strategy Sharpe ratio > 0.5
- **AND** enhanced strategy annual return > simple strategy + 3%
- **AND** enhanced strategy max drawdown remains < 5%

#### Scenario: Walk-forward validation
- **WHEN** running walk-forward analysis (2-year in-sample, 6-month out-of-sample)
- **THEN** out-of-sample performance is within 20% of in-sample expectations

---

### Requirement: Paper Trading Validation
The system SHALL validate enhanced strategy performance through 4 weeks of paper trading before production deployment.

#### Scenario: Parallel strategy comparison
- **WHEN** both simple and enhanced strategies run in parallel on paper account
- **THEN** daily performance metrics are logged for comparison

#### Scenario: Live performance matches backtest
- **WHEN** enhanced strategy completes 4 weeks of paper trading
- **THEN** actual Sharpe ratio is within 20% of backtested Sharpe ratio

#### Scenario: Data pipeline reliability check
- **WHEN** monitoring paper trading for 4 weeks
- **THEN** committee data refresh succeeds 100% of runs
- **AND** politician scoring succeeds 100% of runs
- **AND** no missing politician profiles block strategy execution
