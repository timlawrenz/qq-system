# Implementation Tasks: Corporate Insider Trading Strategy

## 1. Database Schema (Days 1-2)

### 1.1 Migration
- [x] 1.1.1 Create migration to add insider-specific columns to quiver_trades
- [x] 1.1.2 Add relationship column (string) - CEO, CFO, Director, Officer
- [x] 1.1.3 Add shares_held column (bigint) - total shares owned after transaction
- [x] 1.1.4 Add ownership_percent column (decimal) - % ownership after transaction
- [x] 1.1.5 Add trade_type column (string) - Form4, Form144, Form3
- [x] 1.1.6 Run migration in test and dev
- [x] 1.1.7 Verify schema changes

### 1.2 Model Enhancement
- [x] 1.2.1 Add validations for new columns to QuiverTrade
- [x] 1.2.2 Add scope: insiders -> where(trader_source: 'insider')
- [x] 1.2.3 Add scope: c_suite -> where(relationship: ['CEO', 'CFO', 'COO'])
- [x] 1.2.4 Add scope: form4_trades -> where(trade_type: 'Form4')
- [x] 1.2.5 Update existing specs for new fields
- [x] 1.2.6 Update FactoryBot factory for insider trades
- [x] 1.2.7 Write new model specs (~15 tests)

## 2. Data Fetching (Days 3-5)

### 2.1 QuiverClient Enhancement
- [x] 2.1.1 Add fetch_insider_trades(options = {}) method
- [x] 2.1.2 Implement API call to /beta/live/insiders
- [x] 2.1.3 Parse response with new insider-specific fields
- [x] 2.1.4 Map trader_source to 'insider'
- [x] 2.1.5 Handle API errors gracefully
- [x] 2.1.6 Record VCR cassettes for API calls
- [x] 2.1.7 Write QuiverClient specs (~10 tests)

### 2.2 FetchInsiderTrades Command
- [x] 2.2.1 Create FetchInsiderTrades GLCommand
- [x] 2.2.2 Implement deduplication logic (ticker + trader_name + transaction_date)
- [x] 2.2.3 Handle relationship type mapping
- [x] 2.2.4 Parse shares_held and percent_of_holdings
- [x] 2.2.5 Filter out scheduled/automatic trades (if identifiable)
- [x] 2.2.6 Return counts (total, new, updated, errors)
- [x] 2.2.7 Write command specs (~15 tests)

### 2.3 Background Job
- [x] 2.3.1 Create FetchInsiderTradesJob
- [x] 2.3.2 Default to 60 days lookback
- [x] 2.3.3 Add retry logic (3 attempts, exponential backoff)
- [x] 2.3.4 Structured logging
- [x] 2.3.5 Write job spec
- [x] 2.3.6 Manual console testing

## 3. Strategy Implementation (Days 6-10)

### 3.1 InsiderMimicryPortfolio Command
- [x] 3.1.1 Create GenerateInsiderMimicryPortfolio GLCommand
- [x] 3.1.2 Fetch recent insider purchases (30-day window)
- [x] 3.1.3 Filter by relationship type (configurable)
- [x] 3.1.4 Filter out sales trades (purchases only for MVP)
- [x] 3.1.5 Implement position sizing by role weight
- [x] 3.1.6 Calculate equal-weight or role-weighted allocation
- [x] 3.1.7 Return target_positions array
- [x] 3.1.8 Write command specs (~20 tests)

### 3.2 Role-Based Weighting
- [x] 3.2.1 Define role weights: CEO=2.0, CFO=1.5, Director=1.0
- [x] 3.2.2 Calculate weighted position sizes
- [x] 3.2.3 Normalize to sum to 1.0
- [x] 3.2.4 Test weight calculations
- [x] 3.2.5 Make weights configurable

### 3.3 Strategy Configuration
- [ ] 3.3.1 Support filter configuration (relationship types, lookback days)
- [x] 3.3.2 Support position sizing mode (equal-weight vs role-weighted)
- [ ] 3.3.3 Support include_sales flag (default false)
- [x] 3.3.4 Add minimum purchase amount filter

## 4. Integration & Testing (Days 11-12)

### 4.1 Integration Tests
- [x] 4.1.1 End-to-end: API → Database → Strategy → Positions
- [x] 4.1.2 Test with both congressional and insider data
- [x] 4.1.3 Verify no conflicts between trader_source types
- [x] 4.1.4 Test multi-strategy portfolio generation
- [ ] 4.1.5 Write integration specs (~10 tests)

### 4.2 Manual Testing
- [ ] 4.2.1 Fetch real insider data from QuiverQuant
- [ ] 4.2.2 Generate insider portfolio in console
- [ ] 4.2.3 Compare to congressional portfolio
- [ ] 4.2.4 Test edge cases (no trades, all sales, empty portfolio)

## 5. Backtesting (Days 13-15)

### 5.1 Historical Backtest
- [ ] 5.1.1 Fetch 2 years of historical insider trades
- [ ] 5.1.2 Run backtest: insider strategy only
- [ ] 5.1.3 Run backtest: congressional strategy only
- [ ] 5.1.4 Run backtest: combined (50/50 allocation)
- [ ] 5.1.5 Calculate performance metrics (Sharpe, returns, drawdown)
- [ ] 5.1.6 Validate 5-7% annual alpha expectation
- [ ] 5.1.7 Document backtest results

### 5.2 Strategy Comparison
- [ ] 5.2.1 Compare insider vs congressional Sharpe ratios
- [ ] 5.2.2 Analyze correlation between strategies
- [ ] 5.2.3 Test portfolio benefits of running both strategies
- [ ] 5.2.4 Identify optimal allocation between strategies

## 6. Quality Assurance (Day 16)

### 6.1 Code Quality
- [ ] 6.1.1 Run RuboCop (0 offenses)
- [ ] 6.1.2 Run Brakeman (0 warnings)
- [ ] 6.1.3 Run Packwerk check (no violations)
- [ ] 6.1.4 Run Packwerk validate
- [ ] 6.1.5 Verify test coverage >90%

### 6.2 Testing
- [ ] 6.2.1 All unit tests passing (~60 tests)
- [ ] 6.2.2 All integration tests passing
- [ ] 6.2.3 No N+1 queries
- [ ] 6.2.4 VCR cassettes recorded

## 7. Documentation (Day 17)

- [ ] 7.1 Create docs/insider-trading-data.md
- [ ] 7.2 Update README.md with insider strategy section
- [ ] 7.3 Update STRATEGY_ROADMAP.md (mark 1.3 as IMPLEMENTED)
- [ ] 7.4 Update DAILY_TRADING.md with multi-strategy execution
- [ ] 7.5 Document role-weighting methodology

## 8. Deployment & Monitoring (Days 18-20)

### 8.1 Paper Trading (Week 4)
- [ ] 8.1.1 Deploy insider strategy to paper account
- [ ] 8.1.2 Run insider + congressional strategies in parallel
- [ ] 8.1.3 Monitor performance for 1 week
- [ ] 8.1.4 Validate data pipeline reliability
- [ ] 8.1.5 Check for execution errors

### 8.2 Multi-Strategy Framework
- [ ] 8.2.1 Update ExecuteSimpleStrategyJob to support strategy selection
- [ ] 8.2.2 Support running multiple strategies with allocation
- [ ] 8.2.3 Test 50% congressional / 50% insider allocation
- [ ] 8.2.4 Set up per-strategy performance tracking

### 8.3 Production Readiness (Weeks 5-8)
- [ ] 8.3.1 Continue paper trading for 4 weeks total
- [ ] 8.3.2 Validate backtest expectations
- [ ] 8.3.3 Set up alerting for insider data freshness
- [ ] 8.3.4 Monitor disclosure lag (should be <2 days)
- [ ] 8.3.5 Prepare for production rollout
