# Implementation Tasks: Enhanced Congressional Trading Strategy

## 1. Database Schema & Models (Week 1)

### 1.1 Migrations
- [ ] 1.1.1 Create politician_profiles table
- [ ] 1.1.2 Create committees table
- [ ] 1.1.3 Create committee_memberships join table
- [ ] 1.1.4 Create industries table
- [ ] 1.1.5 Create committee_industry_mappings join table
- [ ] 1.1.6 Add politician_id to quiver_trades
- [ ] 1.1.7 Run all migrations in test and dev
- [ ] 1.1.8 Verify schema with db:schema:dump

### 1.2 Models
- [ ] 1.2.1 Create PoliticianProfile model with validations
- [ ] 1.2.2 Create Committee model with validations
- [ ] 1.2.3 Create CommitteeMembership model
- [ ] 1.2.4 Create Industry model
- [ ] 1.2.5 Create CommitteeIndustryMapping model
- [ ] 1.2.6 Update QuiverTrade with politician_profile association
- [ ] 1.2.7 Write model specs (~30 tests)
- [ ] 1.2.8 Create FactoryBot factories for all models

### 1.3 Seed Data
- [ ] 1.3.1 Create YAML file with committee-industry mappings
- [ ] 1.3.2 Create rake task: seed_committees
- [ ] 1.3.3 Create rake task: seed_industries
- [ ] 1.3.4 Create rake task: map_committees_to_industries
- [ ] 1.3.5 Test full seed process

## 2. Services & Background Jobs (Week 2)

### 2.1 Data Fetching Services
- [ ] 2.1.1 Create CommitteeDataFetcher service
- [ ] 2.1.2 Integrate with ProPublica Congress API
- [ ] 2.1.3 Record VCR cassettes for API calls
- [ ] 2.1.4 Write CommitteeDataFetcher specs (~15 tests)
- [ ] 2.1.5 Create StockIndustryClassifier service (keyword matching)
- [ ] 2.1.6 Write StockIndustryClassifier specs (~10 tests)
- [ ] 2.1.7 Manual console testing

### 2.2 Scoring & Analysis Services
- [ ] 2.2.1 Create PoliticianScorer service
- [ ] 2.2.2 Implement win rate calculation logic
- [ ] 2.2.3 Implement average return calculation
- [ ] 2.2.4 Implement quality score formula
- [ ] 2.2.5 Write PoliticianScorer specs (~15 tests)
- [ ] 2.2.6 Create ConsensusDetector service
- [ ] 2.2.7 Write ConsensusDetector specs (~10 tests)

### 2.3 Background Jobs
- [ ] 2.3.1 Create ScorePoliticiansJob
- [ ] 2.3.2 Write ScorePoliticiansJob spec
- [ ] 2.3.3 Create RefreshCommitteeDataJob
- [ ] 2.3.4 Write RefreshCommitteeDataJob spec
- [ ] 2.3.5 Test jobs manually in console

## 3. Strategy Implementation (Week 3)

### 3.1 Enhanced Strategy Command
- [ ] 3.1.1 Create GenerateEnhancedCongressionalPortfolio command
- [ ] 3.1.2 Implement committee filtering logic
- [ ] 3.1.3 Implement quality score filtering
- [ ] 3.1.4 Implement consensus detection
- [ ] 3.1.5 Implement dynamic position sizing
- [ ] 3.1.6 Write command specs (~40 tests)
- [ ] 3.1.7 Test edge cases (empty portfolio, all filtered out)

### 3.2 Integration
- [ ] 3.2.1 Update ExecuteSimpleStrategyJob to support strategy selection
- [ ] 3.2.2 Add configuration for filter parameters
- [ ] 3.2.3 Write integration tests (~10 tests)
- [ ] 3.2.4 Update DAILY_TRADING.md with new strategy option

### 3.3 Backtesting
- [ ] 3.3.1 Backfill politician_id for existing quiver_trades
- [ ] 3.3.2 Fetch committee data and score politicians
- [ ] 3.3.3 Run backtest: simple strategy (baseline)
- [ ] 3.3.4 Run backtest: committee filter only
- [ ] 3.3.5 Run backtest: quality score filter only
- [ ] 3.3.6 Run backtest: consensus boost only
- [ ] 3.3.7 Run backtest: all filters combined
- [ ] 3.3.8 Compare results and validate +3-5% alpha improvement
- [ ] 3.3.9 Document backtest results

## 4. Quality Assurance

### 4.1 Code Quality
- [ ] 4.1.1 Run RuboCop (0 offenses)
- [ ] 4.1.2 Run Brakeman (0 warnings)
- [ ] 4.1.3 Run Packwerk check (no violations)
- [ ] 4.1.4 Run Packwerk validate (valid configuration)
- [ ] 4.1.5 Verify test coverage >90%

### 4.2 Testing
- [ ] 4.2.1 All unit tests passing (~120 tests)
- [ ] 4.2.2 All integration tests passing
- [ ] 4.2.3 No N+1 queries detected
- [ ] 4.2.4 Manual console testing complete

## 5. Documentation

- [ ] 5.1 Create docs/committee-data-sources.md
- [ ] 5.2 Create docs/politician-scoring-methodology.md
- [ ] 5.3 Create docs/industry-classification.md
- [ ] 5.4 Update README.md with enhanced strategy section
- [ ] 5.5 Update STRATEGY_ROADMAP.md (mark 1.2 as IMPLEMENTED)
- [ ] 5.6 Update DAILY_TRADING.md with new configuration options

## 6. Deployment & Monitoring

### 6.1 Paper Trading (Week 4)
- [ ] 6.1.1 Deploy enhanced strategy to paper account
- [ ] 6.1.2 Configure filters (committee=true, min_quality=5.0, consensus=true)
- [ ] 6.1.3 Run both strategies in parallel for 1 week
- [ ] 6.1.4 Monitor daily performance vs backtest
- [ ] 6.1.5 Check for execution errors
- [ ] 6.1.6 Validate data pipeline reliability

### 6.2 Production Readiness (Week 5-8)
- [ ] 6.2.1 Continue paper trading for 4 weeks total
- [ ] 6.2.2 Validate live performance within 20% of backtest
- [ ] 6.2.3 Set up alerting for data quality issues
- [ ] 6.2.4 Set up Sharpe ratio monitoring
- [ ] 6.2.5 Set up alpha decay tracking

### 6.3 Production Rollout (Week 9+)
- [ ] 6.3.1 If validated: Allocate 25% capital to enhanced strategy
- [ ] 6.3.2 Week 10: Increase to 50% allocation
- [ ] 6.3.3 Week 11: Increase to 75% allocation
- [ ] 6.3.4 Week 12: Full 100% allocation
- [ ] 6.3.5 Continue monitoring for 3 months
