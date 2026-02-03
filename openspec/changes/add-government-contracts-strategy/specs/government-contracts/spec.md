## ADDED Requirements

### Requirement: Government Contract Data Fetching
The system SHALL fetch government contract award data from the QuiverQuant API and persist it to a dedicated government_contracts table.

#### Scenario: Fetch recent contract awards
- **WHEN** FetchGovernmentContracts command is executed with default parameters
- **THEN** contract awards from the last 90 days are fetched from /beta/bulk/govcontracts endpoint
- **AND** contracts are persisted with all available fields

#### Scenario: Parse contract-specific fields
- **WHEN** processing a contract from the API
- **THEN** the system extracts contract_value, agency, award_date, contract_id, contract_type
- **AND** stores ticker and company name

#### Scenario: Deduplicate contracts by contract_id
- **WHEN** a contract with the same contract_id already exists
- **THEN** the existing record is updated with latest data
- **AND** no duplicate record is created

#### Scenario: Handle API errors gracefully
- **WHEN** the QuiverQuant API returns error
- **THEN** the command fails with clear error message
- **AND** no partial data is persisted

---

### Requirement: Materiality Assessment
The system SHALL filter government contracts based on their materiality to the recipient company, calculated as a percentage of annual revenue.

#### Scenario: Calculate materiality percentage
- **WHEN** a company with $1B annual revenue receives a $50M contract
- **THEN** materiality = 5.0% (50M / 1000M * 100)

#### Scenario: Filter by minimum materiality threshold
- **WHEN** strategy is configured with min_materiality_pct = 1.0
- **THEN** only contracts representing ≥1% of company revenue are included

#### Scenario: Apply minimum absolute value filter
- **WHEN** strategy is configured with min_contract_value = $10M
- **THEN** contracts below $10M are excluded regardless of materiality
- **AND** both filters must pass for inclusion

#### Scenario: Handle missing revenue data
- **WHEN** annual revenue data is unavailable for a ticker
- **THEN** the contract is included (default: assume material)
- **AND** a warning is logged for manual review

---

### Requirement: Fundamentals / Company Profile Integration
The system SHALL fetch and cache company profile data per ticker, including `sector`, `industry`, and (if available) annual revenue for materiality calculations.

#### Scenario: Fetch profile from FMP
- **WHEN** FundamentalDataService.get_company_profile('LMT') is called and no cache exists
- **THEN** company profile is fetched from Financial Modeling Prep (FMP)
- **AND** cached in the database for 30+ days

#### Scenario: Use cached sector/industry
- **WHEN** FundamentalDataService.get_sector('LMT') is called
- **THEN** sector is returned from the cached company profile
- **AND** no external API call is made

#### Scenario: Use cached annual revenue (optional)
- **WHEN** FundamentalDataService.get_annual_revenue('LMT') is called
- **THEN** annual revenue is returned from the cached profile if present

#### Scenario: Rate-limit to fit Basic plan
- **WHEN** many tickers are encountered in contracts
- **THEN** only unknown/un-cached tickers trigger FMP calls
- **AND** the system stays under 250 calls/day by design

#### Scenario: Handle missing profile data
- **WHEN** sector/industry/revenue are unavailable for a ticker
- **THEN** FundamentalDataService returns nil for those fields
- **AND** the contracts strategy applies its configured fallback behavior

---

### Requirement: Contracts Portfolio Generation
The system SHALL generate target portfolios based on recent government contract awards that pass materiality filters.

#### Scenario: Equal-weight qualifying contracts
- **WHEN** GenerateContractsPortfolio is called with equal-weight mode
- **THEN** all qualifying contracts receive equal position sizes
- **AND** positions sum to 100% of allocated capital

#### Scenario: Weight by materiality percentage
- **WHEN** using materiality-weighted mode
- **THEN** contracts representing 5% of revenue receive 2x weight vs 1% contracts
- **AND** weights are normalized to sum to 1.0

#### Scenario: 7-day lookback window
- **WHEN** generating portfolio on January 8
- **THEN** only contracts awarded January 1-7 are included
- **AND** older contracts are ignored

#### Scenario: Empty portfolio when no qualifying contracts
- **WHEN** no contracts pass materiality filters in lookback window
- **THEN** empty target_positions array is returned
- **AND** no positions are opened

---

### Requirement: Time-Based Position Exits
The system SHALL automatically close positions after a configured holding period to capture the contract announcement effect.

#### Scenario: 5-day holding period
- **WHEN** a position is entered on contract award date
- **THEN** position is automatically closed 5 trading days later
- **AND** regardless of profit or loss

#### Scenario: 10-day holding period
- **WHEN** strategy is configured with holding_period_days = 10
- **THEN** positions are held for 10 trading days

#### Scenario: Track entry date per position
- **WHEN** a position is opened
- **THEN** the entry date is recorded
- **AND** exit is scheduled for entry_date + holding_period_days

---

### Requirement: Sector-Specific Thresholds
The system SHALL support different materiality thresholds for different industry sectors.

#### Scenario: Defense sector lower threshold
- **WHEN** a defense company (e.g., Lockheed Martin) receives contract
- **THEN** materiality threshold is 0.5% (lower than default 1%)
- **AND** more contracts qualify (contracts are normal business)

#### Scenario: Technology sector higher threshold
- **WHEN** a tech company receives government contract
- **THEN** materiality threshold is 2.0% (higher than default)
- **AND** only significant contracts qualify (contracts are unusual)

#### Scenario: Services sector default threshold
- **WHEN** a services company receives contract
- **THEN** default 1.0% threshold applies

---

### Requirement: Agency Performance Tracking
The system SHALL track historical performance of contracts by awarding agency to weight future contracts.

#### Scenario: Track CAR by agency
- **WHEN** backtesting contracts strategy
- **THEN** calculate cumulative abnormal return (CAR) by agency
- **AND** store DoD, NASA, DHS, etc. performance separately

#### Scenario: Weight by agency historical performance
- **WHEN** DoD contracts historically show 3% CAR vs NASA 1% CAR
- **THEN** DoD contracts receive 1.5x weight multiplier
- **AND** positions are sized accordingly

#### Scenario: Preferred agency filtering
- **WHEN** strategy is configured with preferred_agencies = ['DoD', 'NASA']
- **THEN** only contracts from these agencies are included

---

### Requirement: Strategy Configuration
The system SHALL support configurable parameters for the government contracts strategy.

#### Scenario: Configure lookback period
- **WHEN** strategy is configured with lookback_days = 14
- **THEN** contracts from the last 14 days are considered

#### Scenario: Configure materiality threshold
- **WHEN** strategy is configured with min_materiality_pct = 2.0
- **THEN** only contracts ≥2% of revenue are included

#### Scenario: Configure minimum contract value
- **WHEN** strategy is configured with min_contract_value = $25M
- **THEN** contracts below $25M are excluded

#### Scenario: Configure holding period
- **WHEN** strategy is configured with holding_period_days = 7
- **THEN** positions are held for exactly 7 trading days

---

### Requirement: Multi-Strategy Integration
The system SHALL support running government contracts strategy alongside congressional and insider strategies.

#### Scenario: Allocate capital across three strategies
- **WHEN** ExecuteMultiStrategyJob is configured with 33% congressional, 33% insider, 34% contracts
- **THEN** capital is split appropriately across all three strategies

#### Scenario: Uncorrelated signal validation
- **WHEN** monitoring strategy correlation
- **THEN** contracts strategy should have <0.3 correlation with congressional
- **AND** <0.4 correlation with insider (different timing)

---

### Requirement: Data Quality Validation
The system SHALL validate government contract data quality and completeness.

#### Scenario: Validate contract_value is positive
- **WHEN** processing a contract
- **THEN** contract_value must be > 0
- **AND** negative or zero values are logged as errors

#### Scenario: Validate award_date is recent
- **WHEN** processing contracts
- **THEN** award_date must be within last 180 days
- **AND** older contracts are flagged (possible data issue)

#### Scenario: Validate ticker mapping
- **WHEN** contract company name is mapped to ticker
- **THEN** verify ticker exists and is tradeable
- **AND** flag unmapped or delisted tickers

---

### Requirement: Backtest Validation
The system SHALL validate that government contracts strategy delivers positive cumulative abnormal returns (CAR).

#### Scenario: Run 2-year historical backtest
- **WHEN** backtesting contracts strategy over 2023-2025
- **THEN** strategy shows positive CAR in days following announcement
- **AND** Sharpe ratio > 0.5
- **AND** hit rate (winning trades) > 55%

#### Scenario: Validate 5-day vs 10-day holding periods
- **WHEN** comparing different holding periods
- **THEN** 5-day period shows optimal Sharpe ratio
- **AND** longer periods dilute alpha

#### Scenario: Sector performance analysis
- **WHEN** analyzing by sector
- **THEN** defense/aerospace shows strongest CAR
- **AND** technology shows moderate CAR
- **AND** services shows weakest CAR

---

### Requirement: Paper Trading Validation
The system SHALL validate contracts strategy through 4 weeks of paper trading.

#### Scenario: Monitor contract announcements
- **WHEN** new contracts are announced
- **THEN** positions are opened within 1 trading day
- **AND** execution is timely

#### Scenario: Validate holding period exits
- **WHEN** holding period expires
- **THEN** positions are automatically closed
- **AND** no manual intervention needed

#### Scenario: Track announcement-to-execution lag
- **WHEN** monitoring paper trading
- **THEN** average lag should be <24 hours
- **AND** no stale contract data
