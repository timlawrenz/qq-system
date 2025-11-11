# Implementation Tasks: Insider Consensus Detection

## Prerequisites

⚠️ **This change depends on `add-corporate-insider-strategy` being completed first.**

---

## 1. Database Schema (Days 1-2)

### 1.1 Consensus Tracking
- [ ] 1.1.1 Create migration for consensus tracking
- [ ] 1.1.2 Add insider_consensus_count (integer) - number of insiders buying
- [ ] 1.1.3 Add insider_conviction_score (decimal) - calculated conviction strength
- [ ] 1.1.4 Add first_purchase_flag (boolean) - marks CEO's first-ever purchase
- [ ] 1.1.5 Add consensus_window_start (date) - start of consensus window
- [ ] 1.1.6 Run migration in test and dev
- [ ] 1.1.7 Add indexes on company + transaction_date for consensus queries

### 1.2 Model Enhancement
- [ ] 1.2.1 Add scope: with_consensus -> where('insider_consensus_count >= ?', 2)
- [ ] 1.2.2 Add scope: high_conviction -> where('insider_conviction_score >= ?', 7.0)
- [ ] 1.2.3 Add scope: first_purchases -> where(first_purchase_flag: true)
- [ ] 1.2.4 Update QuiverTrade specs for new fields
- [ ] 1.2.5 Update factories

## 2. Consensus Detection Services (Days 3-7)

### 2.1 InsiderConsensusDetector Service
- [ ] 2.1.1 Create InsiderConsensusDetector service
- [ ] 2.1.2 Implement detect_company_consensus(ticker, window_days: 30)
- [ ] 2.1.3 Group insider purchases by company within window
- [ ] 2.1.4 Return hash: { ticker => { count: X, insiders: [...] } }
- [ ] 2.1.5 Detect same-stock clustering (multiple companies → same stock)
- [ ] 2.1.6 Write comprehensive specs (~20 tests)

### 2.2 InsiderConvictionScorer Service
- [ ] 2.2.1 Create InsiderConvictionScorer service
- [ ] 2.2.2 Implement score_consensus(ticker, insider_trades)
- [ ] 2.2.3 Calculate base score: number of insiders buying
- [ ] 2.2.4 Weight by seniority: CEO=3x, CFO=2x, Director=1x
- [ ] 2.2.5 Weight by transaction size (percent_of_holdings)
- [ ] 2.2.6 Combine factors into 0-10 conviction score
- [ ] 2.2.7 Write specs with various scenarios (~15 tests)

### 2.3 BehavioralShiftDetector Service
- [ ] 2.3.1 Create BehavioralShiftDetector service
- [ ] 2.3.2 Implement detect_first_purchase(insider_name, ticker)
- [ ] 2.3.3 Query historical trades to check if first purchase
- [ ] 2.3.4 Flag CEO's first-ever open-market buy (high signal)
- [ ] 2.3.5 Detect sudden increase in purchase frequency
- [ ] 2.3.6 Write specs (~10 tests)

## 3. Strategy Enhancement (Days 8-10)

### 3.1 Enhance InsiderMimicryPortfolio
- [ ] 3.1.1 Add consensus detection to GenerateInsiderMimicryPortfolio
- [ ] 3.1.2 Call InsiderConsensusDetector for recent trades
- [ ] 3.1.3 Calculate conviction scores for consensus stocks
- [ ] 3.1.4 Apply consensus multiplier to position sizes (1.5-2.0x)
- [ ] 3.1.5 Update command specs (~15 tests)

### 3.2 Position Sizing Logic
- [ ] 3.2.1 Define conviction multipliers:
  - [ ] 2 insiders = 1.5x weight
  - [ ] 3+ insiders = 2.0x weight
  - [ ] First purchase flag = additional 1.2x boost
- [ ] 3.2.2 Calculate final weight = base * role_weight * consensus_multiplier
- [ ] 3.2.3 Normalize all weights to sum to 1.0
- [ ] 3.2.4 Test weight calculations

### 3.3 Configuration
- [ ] 3.3.1 Add consensus_boost flag (default: true)
- [ ] 3.3.2 Add min_insiders_for_consensus (default: 2)
- [ ] 3.3.3 Add consensus_window_days (default: 30)
- [ ] 3.3.4 Add consensus_multiplier config (default: 1.5)
- [ ] 3.3.5 Make all parameters configurable

## 4. Background Processing (Days 11-12)

### 4.1 Consensus Calculation Job
- [ ] 4.1.1 Create CalculateInsiderConsensusJob
- [ ] 4.1.2 Run daily after FetchInsiderTradesJob
- [ ] 4.1.3 Calculate consensus metrics for all recent trades
- [ ] 4.1.4 Update insider_consensus_count and insider_conviction_score
- [ ] 4.1.5 Flag first purchases
- [ ] 4.1.6 Write job spec

### 4.2 Integration
- [ ] 4.2.1 Chain jobs: FetchInsiderTrades → CalculateInsiderConsensus
- [ ] 4.2.2 Test job chaining in console
- [ ] 4.2.3 Add error handling and retry logic

## 5. Backtesting (Days 13-15)

### 5.1 Consensus Strategy Backtest
- [ ] 5.1.1 Backfill consensus metrics for historical trades
- [ ] 5.1.2 Run backtest: basic insider strategy (baseline)
- [ ] 5.1.3 Run backtest: insider + consensus enhancement
- [ ] 5.1.4 Compare Sharpe ratios and returns
- [ ] 5.1.5 Validate +2-4% alpha improvement
- [ ] 5.1.6 Document results

### 5.2 Sensitivity Analysis
- [ ] 5.2.1 Test different consensus windows (15, 30, 45 days)
- [ ] 5.2.2 Test different multipliers (1.3x, 1.5x, 2.0x)
- [ ] 5.2.3 Test minimum insider thresholds (2, 3, 4+)
- [ ] 5.2.4 Identify optimal parameters
- [ ] 5.2.5 Document sensitivity analysis

## 6. Quality Assurance (Day 16)

### 6.1 Code Quality
- [ ] 6.1.1 Run RuboCop (0 offenses)
- [ ] 6.1.2 Run Brakeman (0 warnings)
- [ ] 6.1.3 Run Packwerk check (no violations)
- [ ] 6.1.4 Verify test coverage >90%

### 6.2 Testing
- [ ] 6.2.1 All unit tests passing (~50 tests)
- [ ] 6.2.2 All integration tests passing
- [ ] 6.2.3 No N+1 queries in consensus detection
- [ ] 6.2.4 Performance testing (should add <2 sec)

## 7. Documentation (Day 17)

- [ ] 7.1 Update docs/insider-trading-data.md with consensus methodology
- [ ] 7.2 Create docs/insider-consensus-scoring.md
- [ ] 7.3 Update README.md with consensus enhancement
- [ ] 7.4 Update STRATEGY_ROADMAP.md (mark 1.4 as IMPLEMENTED)
- [ ] 7.5 Document conviction score formula

## 8. Deployment & Monitoring (Days 18-20)

### 8.1 Paper Trading
- [ ] 8.1.1 Deploy consensus-enhanced strategy to paper account
- [ ] 8.1.2 Run basic vs enhanced in parallel
- [ ] 8.1.3 Monitor for 2 weeks
- [ ] 8.1.4 Validate consensus detection accuracy
- [ ] 8.1.5 Check conviction score distribution

### 8.2 Performance Validation
- [ ] 8.2.1 Compare to backtest expectations
- [ ] 8.2.2 Validate consensus multiplier effectiveness
- [ ] 8.2.3 Monitor for false positives (random clustering)
- [ ] 8.2.4 Check first-purchase flag accuracy

### 8.3 Production Readiness
- [ ] 8.3.1 Continue paper trading for 4 weeks total
- [ ] 8.3.2 Gradual rollout: 25% → 50% → 100% over 4 weeks
- [ ] 8.3.3 Set up consensus detection monitoring
- [ ] 8.3.4 Alert on unusually high/low consensus rates
