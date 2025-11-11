# Implementation Tasks: Government Contracts Strategy

## 1. Database Schema & Models (Days 1-3)

### 1.1 GovernmentContract Model
- [ ] 1.1.1 Create government_contracts table migration
- [ ] 1.1.2 Add ticker (string, indexed)
- [ ] 1.1.3 Add company (string)
- [ ] 1.1.4 Add contract_value (decimal) - total obligated amount
- [ ] 1.1.5 Add award_date (date, indexed)
- [ ] 1.1.6 Add agency (string) - awarding agency (DoD, NASA, etc.)
- [ ] 1.1.7 Add contract_type (string) - procurement, R&D, services
- [ ] 1.1.8 Add description (text)
- [ ] 1.1.9 Add contract_id (string, unique) - government contract number
- [ ] 1.1.10 Add disclosed_at (datetime)
- [ ] 1.1.11 Run migration in test and dev

### 1.2 Model Implementation
- [ ] 1.2.1 Create GovernmentContract model with validations
- [ ] 1.2.2 Add scope: recent(days) -> where('award_date >= ?', days.ago)
- [ ] 1.2.3 Add scope: by_agency(agency) -> where(agency: agency)
- [ ] 1.2.4 Add scope: minimum_value(amount) -> where('contract_value >= ?', amount)
- [ ] 1.2.5 Add scope: for_ticker(ticker) -> where(ticker: ticker)
- [ ] 1.2.6 Write model specs (~20 tests)
- [ ] 1.2.7 Create FactoryBot factory

## 2. Data Fetching (Days 4-7)

### 2.1 QuiverClient Enhancement
- [ ] 2.1.1 Add fetch_government_contracts(options = {}) method
- [ ] 2.1.2 Implement API call to /beta/bulk/govcontracts
- [ ] 2.1.3 Parse response with contract-specific fields
- [ ] 2.1.4 Handle pagination (if endpoint supports it)
- [ ] 2.1.5 Record VCR cassettes
- [ ] 2.1.6 Write QuiverClient specs (~10 tests)

### 2.2 FetchGovernmentContracts Command
- [ ] 2.2.1 Create FetchGovernmentContracts GLCommand
- [ ] 2.2.2 Implement deduplication by contract_id
- [ ] 2.2.3 Parse and normalize agency names
- [ ] 2.2.4 Map contract types (if available in API)
- [ ] 2.2.5 Return counts (total, new, updated, errors)
- [ ] 2.2.6 Write command specs (~15 tests)

### 2.3 Background Job
- [ ] 2.3.1 Create FetchGovernmentContractsJob
- [ ] 2.3.2 Default to 90 days lookback
- [ ] 2.3.3 Add retry logic (3 attempts)
- [ ] 2.3.4 Structured logging
- [ ] 2.3.5 Write job spec
- [ ] 2.3.6 Manual console testing

## 3. Fundamental Data Integration (Days 8-10)

### 3.1 FundamentalDataService
- [ ] 3.1.1 Create FundamentalDataService
- [ ] 3.1.2 Implement get_annual_revenue(ticker) method
- [ ] 3.1.3 Option 1: Integrate with Alpaca fundamentals (if available)
- [ ] 3.1.4 Option 2: Integrate with external API (FMP or Alpha Vantage)
- [ ] 3.1.5 Option 3: Hardcode revenue for top 100 defense contractors (MVP)
- [ ] 3.1.6 Cache revenue data (30-day TTL)
- [ ] 3.1.7 Write service specs (~15 tests)

### 3.2 Revenue Data Storage (Optional)
- [ ] 3.2.1 Create company_fundamentals table (optional)
- [ ] 3.2.2 Store ticker, annual_revenue, fiscal_year, updated_at
- [ ] 3.2.3 Add refresh job to update quarterly

## 4. Materiality Assessment (Days 11-13)

### 4.1 MaterialityCalculator Service
- [ ] 4.1.1 Create MaterialityCalculator service
- [ ] 4.1.2 Implement calculate_materiality(contract_value, annual_revenue)
- [ ] 4.1.3 Return percentage: (contract_value / annual_revenue) * 100
- [ ] 4.1.4 Handle missing revenue data (default: include contract)
- [ ] 4.1.5 Write specs (~10 tests)

### 4.2 Filtering Logic
- [ ] 4.2.1 Define minimum materiality threshold (default: 1% of revenue)
- [ ] 4.2.2 Define minimum absolute value (default: $10M)
- [ ] 4.2.3 Sector-specific thresholds (defense: 0.5%, tech: 2%)
- [ ] 4.2.4 Make thresholds configurable

## 5. Strategy Implementation (Days 14-17)

### 5.1 GenerateContractsPortfolio Command
- [ ] 5.1.1 Create GenerateContractsPortfolio GLCommand
- [ ] 5.1.2 Fetch recent contracts (last 7 days by default)
- [ ] 5.1.3 Filter by materiality threshold
- [ ] 5.1.4 Calculate position sizes based on contract value
- [ ] 5.1.5 Return target_positions array
- [ ] 5.1.6 Write command specs (~20 tests)

### 5.2 Position Sizing Logic
- [ ] 5.2.1 Option 1: Equal-weight all qualifying contracts
- [ ] 5.2.2 Option 2: Weight by materiality percentage
- [ ] 5.2.3 Option 3: Weight by contract_value as % of portfolio
- [ ] 5.2.4 Implement chosen approach
- [ ] 5.2.5 Normalize weights to sum to 1.0

### 5.3 Time-Based Exit Logic
- [ ] 5.3.1 Add contract_entry_date tracking to positions
- [ ] 5.3.2 Implement 5-day or 10-day holding period
- [ ] 5.3.3 Automatic position closure after holding period
- [ ] 5.3.4 Test exit logic

### 5.4 Configuration
- [ ] 5.4.1 Add lookback_days (default: 7)
- [ ] 5.4.2 Add min_materiality_pct (default: 1.0)
- [ ] 5.4.3 Add min_contract_value (default: $10M)
- [ ] 5.4.4 Add holding_period_days (default: 5)
- [ ] 5.4.5 Add sector_thresholds hash (optional)

## 6. Sector-Specific Logic (Days 18-19)

### 6.1 Sector Classification
- [ ] 6.1.1 Create SectorClassifier service (reuse from congressional if available)
- [ ] 6.1.2 Map tickers to sectors (Defense, Aerospace, Tech, Services)
- [ ] 6.1.3 Apply sector-specific materiality thresholds

### 6.2 Agency Analysis
- [ ] 6.2.1 Track historical performance by agency (DoD, NASA, etc.)
- [ ] 6.2.2 Weight contracts from high-performing agencies higher
- [ ] 6.2.3 Optional: Filter by preferred agencies

## 7. Backtesting (Days 20-22)

### 7.1 Historical Backtest
- [ ] 7.1.1 Fetch 2 years of historical contract data
- [ ] 7.1.2 Backfill revenue data for contract recipients
- [ ] 7.1.3 Run backtest with 5-day holding period
- [ ] 7.1.4 Run backtest with 10-day holding period
- [ ] 7.1.5 Calculate performance metrics (Sharpe, CAR, hit rate)
- [ ] 7.1.6 Validate positive CAR expectation
- [ ] 7.1.7 Document results

### 7.2 Sensitivity Analysis
- [ ] 7.2.1 Test different materiality thresholds (0.5%, 1%, 2%)
- [ ] 7.2.2 Test different holding periods (3, 5, 7, 10 days)
- [ ] 7.2.3 Test minimum contract values ($5M, $10M, $25M)
- [ ] 7.2.4 Identify optimal parameters
- [ ] 7.2.5 Document sensitivity analysis

## 8. Quality Assurance (Day 23)

### 8.1 Code Quality
- [ ] 8.1.1 Run RuboCop (0 offenses)
- [ ] 8.1.2 Run Brakeman (0 warnings)
- [ ] 8.1.3 Run Packwerk check (no violations)
- [ ] 8.1.4 Verify test coverage >90%

### 8.2 Testing
- [ ] 8.2.1 All unit tests passing (~70 tests)
- [ ] 8.2.2 All integration tests passing
- [ ] 8.2.3 No N+1 queries
- [ ] 8.2.4 VCR cassettes recorded

## 9. Documentation (Day 24)

- [ ] 9.1 Create docs/government-contracts-data.md
- [ ] 9.2 Create docs/materiality-assessment.md
- [ ] 9.3 Update README.md with contracts strategy
- [ ] 9.4 Update STRATEGY_ROADMAP.md (mark 1.5 as IMPLEMENTED)
- [ ] 9.5 Document sector-specific thresholds

## 10. Deployment & Monitoring (Days 25-28)

### 10.1 Paper Trading (Week 5)
- [ ] 10.1.1 Deploy contracts strategy to paper account
- [ ] 10.1.2 Monitor for 2 weeks
- [ ] 10.1.3 Validate materiality filtering accuracy
- [ ] 10.1.4 Check holding period exits
- [ ] 10.1.5 Verify data pipeline reliability

### 10.2 Multi-Strategy Integration
- [ ] 10.2.1 Test contracts strategy alongside congressional + insider
- [ ] 10.2.2 Validate uncorrelated returns (different signal timing)
- [ ] 10.2.3 Test capital allocation across 3 strategies
- [ ] 10.2.4 Monitor combined portfolio metrics

### 10.3 Production Readiness (Weeks 6-9)
- [ ] 10.3.1 Continue paper trading for 4 weeks total
- [ ] 10.3.2 Validate backtest expectations
- [ ] 10.3.3 Set up contract announcement monitoring
- [ ] 10.3.4 Alert on large contracts (>$100M)
- [ ] 10.3.5 Prepare for production rollout
