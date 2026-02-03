# Implementation Tasks: Add Performance Dashboard

## 1. Database & Models

- [x] 1.1 Create migration `create_performance_snapshots`
  - [x] 1.1.1 Add table with all required columns (snapshot_date, snapshot_type, strategy_name, metrics, etc.)
  - [x] 1.1.2 Add indexes on `snapshot_date`, `strategy_name`, and `snapshot_type`
  - [x] 1.1.3 Add compound index on `[snapshot_date, strategy_name, snapshot_type]`
  - [x] 1.1.4 Run migration in development and test environments
- [x] 1.2 Create `PerformanceSnapshot` model in `packs/performance_reporting/app/models/`
  - [x] 1.2.1 Add validations: presence of snapshot_date, snapshot_type, strategy_name
  - [x] 1.2.2 Add enum for snapshot_type: [:daily, :weekly]
  - [x] 1.2.3 Add scopes: `daily`, `weekly`, `by_strategy`, `between_dates`
  - [x] 1.2.4 Add method `to_report_hash` for JSON serialization
- [x] 1.3 Create pack structure `packs/performance_reporting/`
  - [x] 1.3.1 Initialize with `package.yml`
  - [x] 1.3.2 Create `app/models/`, `app/services/`, `app/commands/`, `app/jobs/` directories
  - [x] 1.3.3 Update Packwerk dependencies in `package.yml`

## 2. Core Services

- [x] 2.1 Create `PerformanceCalculator` service in `packs/performance_reporting/app/services/`
  - [x] 2.1.1 Implement `calculate_sharpe_ratio(daily_returns, risk_free_rate = 0.045)`
  - [x] 2.1.2 Implement `calculate_max_drawdown(equity_values)`
  - [x] 2.1.3 Implement `calculate_win_rate(trades)`
  - [x] 2.1.4 Implement `calculate_volatility(daily_returns)`
  - [x] 2.1.5 Implement `calculate_calmar_ratio(annualized_return, max_drawdown)`
  - [x] 2.1.6 Implement `annualized_return(equity_start, equity_end, days)`
  - [x] 2.1.7 Add error handling for insufficient data (return nil + log warning)
- [x] 2.2 Create `BenchmarkComparator` service in `packs/performance_reporting/app/services/`
  - [x] 2.2.1 Implement `fetch_spy_returns(start_date, end_date)` using AlpacaService
  - [x] 2.2.2 Implement `calculate_alpha(portfolio_return, spy_return)`
  - [x] 2.2.3 Implement `calculate_beta(portfolio_returns, spy_returns)`
  - [x] 2.2.4 Add error handling for API failures (return nil + log error)
  - [x] 2.2.5 Cache SPY data daily to minimize API calls

## 3. Command Implementation

- [x] 3.1 Create `GeneratePerformanceReport` command in `packs/performance_reporting/app/commands/`
  - [x] 3.1.1 Define requires: `start_date` (optional), `end_date` (optional), `strategy_name` (optional)
  - [x] 3.1.2 Define returns: `report_hash`, `file_path`, `snapshot_id`
  - [x] 3.1.3 Implement main logic:
    - Fetch account equity history from AlpacaService
    - Fetch all trades from AlpacaOrder for period
    - Calculate daily returns from equity history
    - Call PerformanceCalculator for all metrics
    - Call BenchmarkComparator for SPY comparison
    - Build comparison hash if multiple strategies available
  - [x] 3.1.4 Create PerformanceSnapshot record
  - [x] 3.1.5 Save report JSON to `tmp/performance_reports/`
  - [x] 3.1.6 Add rollback method to clean up snapshot on failure
  - [x] 3.1.7 Add comprehensive error handling and logging

## 4. Scheduled Execution (Cron)

- [x] 4.1 Add rake task `performance:weekly_report` (cron entrypoint)
  - [x] 4.1.1 Runs `GeneratePerformanceReport` for configured strategies
  - [x] 4.1.2 Exits non-zero on failure (cron-friendly)
- [x] 4.2 (Optional) Keep `GeneratePerformanceReportJob` for future job-runner support
  - [x] 4.2.1 Implement `perform` method to call GeneratePerformanceReport command
  - [x] 4.2.2 Add retry logic: max 3 attempts with exponential backoff
  - [x] 4.2.3 Set job to run for all active strategies

## 5. Data Access Layer

- [x] 5.1 Add methods to `AlpacaService` for equity history
  - [x] 5.1.1 Implement `account_equity_history(start_date, end_date)` to fetch daily snapshots
  - [x] 5.1.2 Cache results to minimize API calls
- [ ] 5.2 Add scopes to `AlpacaOrder` for trade analysis
  - [ ] 5.2.1 Add `closed_trades` scope (status: filled, closed)
  - [ ] 5.2.2 Add `between_dates(start_date, end_date)` scope
  - [ ] 5.2.3 Add `winning_trades` scope (filled_avg_price > some threshold for profit)

## 6. Testing

- [x] 6.1 Unit tests for `PerformanceCalculator` service
  - [x] 6.1.1 Test Sharpe ratio calculation with valid data
  - [x] 6.1.2 Test Sharpe ratio with insufficient data (returns nil)
  - [x] 6.1.3 Test max drawdown calculation with various scenarios
  - [x] 6.1.4 Test win rate calculation
  - [x] 6.1.5 Test volatility calculation
  - [x] 6.1.6 Test Calmar ratio calculation
- [ ] 6.2 Unit tests for `BenchmarkComparator` service
  - [ ] 6.2.1 Test SPY data fetching with VCR cassette
  - [ ] 6.2.2 Test alpha calculation
  - [ ] 6.2.3 Test beta calculation
  - [ ] 6.2.4 Test API failure handling
- [ ] 6.3 Unit tests for `GeneratePerformanceReport` command
  - [ ] 6.3.1 Test successful report generation
  - [ ] 6.3.2 Test report with missing Simple strategy data
  - [ ] 6.3.3 Test report with insufficient data for Sharpe ratio
  - [ ] 6.3.4 Test rollback on failure
  - [ ] 6.3.5 Test file creation in tmp/performance_reports/ (includes portfolio suffix)
- [x] 6.4 Unit tests for `PerformanceSnapshot` model
  - [x] 6.4.1 Test validations
  - [x] 6.4.2 Test scopes (daily, weekly, by_strategy)
  - [x] 6.4.3 Test `to_report_hash` serialization
- [ ] 6.5 Integration test for weekly report cron entrypoint
  - [ ] 6.5.1 `rake performance:weekly_report` exits 0 on success
  - [ ] 6.5.2 `rake performance:weekly_report` exits non-zero on failure
  - [ ] 6.5.3 Creates PerformanceSnapshot record(s)
  - [ ] 6.5.4 Creates JSON report file(s) under tmp/performance_reports/ (per-mode, non-clobbering)

## 7. Documentation

- [x] 7.1 Create `packs/performance_reporting/README.md`
  - [x] 7.1.1 Document purpose and capabilities
  - [x] 7.1.2 Provide usage examples
  - [x] 7.1.3 Document metrics calculations
- [ ] 7.2 Update main README.md
  - [ ] 7.2.1 Add section on performance reporting
  - [ ] 7.2.2 Link to weekly report files location
- [x] 7.3 Create `docs/operations/performance-reports.md`
  - [x] 7.3.1 Explain how to read reports
  - [x] 7.3.2 Provide interpretation guide for metrics
  - [x] 7.3.3 Document manual report generation

## 8. Deployment & Validation

- [ ] 8.1 Run all tests: `bundle exec rspec`
- [ ] 8.2 Run linters: `bundle exec rubocop`
- [ ] 8.3 Run security scan: `bundle exec brakeman --no-pager`
- [ ] 8.4 Run Packwerk validation: `bundle exec packwerk check && bundle exec packwerk validate`
- [ ] 8.5 Manually generate first report to verify end-to-end workflow
- [ ] 8.6 Verify cron entry is installed for weekly report generation
- [ ] 8.7 Verify first automated weekly report generation ran successfully
- [ ] 8.8 Verify report accuracy (paper vs live separated) by comparing to manual calculations

## 9. Dashboard Snapshot Payload (supports DB-only UI)

- [x] 9.1 Extend `GeneratePerformanceReport` to also store dashboard-oriented account snapshot data in `PerformanceSnapshot#metadata`
  - [x] 9.1.1 cash, invested, cash_pct, invested_pct
  - [x] 9.1.2 positions array (symbol, side, qty, market_value)
  - [x] 9.1.3 top_positions (top 5 by market_value)
  - [x] 9.1.4 concentration_pct + concentration_symbol
  - [x] 9.1.5 snapshot_captured_at timestamp
- [x] 9.2 Add tests verifying metadata keys exist for generated snapshots
- [x] 9.3 Document the metadata schema in `packs/performance_reporting/README.md`

## 10. Final Checklist

- [ ] 9.1 All tests passing (350+ examples, 0 failures)
- [ ] 9.2 No RuboCop offenses
- [ ] 9.3 No Brakeman security warnings
- [ ] 9.4 Packwerk boundaries enforced
- [ ] 9.5 Weekly cron successfully scheduled
- [ ] 9.6 First report generated and validated
- [ ] 9.7 Documentation complete and accurate
- [ ] 9.8 Code reviewed and approved
- [ ] 9.9 Ready to merge to main branch


---

**Estimated Effort**: 12 hours (~1.5 days)  
**Prerequisites**: None (uses existing AlpacaService and models)  
**Risk**: Low (additive only, no changes to trading logic)
