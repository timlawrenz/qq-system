# Capability: Performance Reporting

Track and report live trading performance with automated weekly reports, strategy comparisons, and benchmark analysis.

## ADDED Requirements

### Requirement: Performance Snapshot Storage
The system SHALL store daily and weekly performance snapshots in the `performance_snapshots` table with the following attributes:
- `snapshot_date` (date, indexed) - Date of the snapshot
- `snapshot_type` (string) - Either "daily" or "weekly"
- `strategy_name` (string) - Label for the portfolio being tracked (e.g., "Blended Portfolio (paper)", "Blended Portfolio (live)")
- `total_equity` (decimal) - Total account equity at snapshot time
- `total_pnl` (decimal) - Cumulative profit/loss since inception
- `sharpe_ratio` (decimal) - Annualized Sharpe ratio
- `max_drawdown_pct` (decimal) - Maximum drawdown percentage
- `volatility` (decimal) - Annualized volatility (standard deviation of returns)
- `win_rate` (decimal) - Percentage of winning trades
- `total_trades` (integer) - Total number of trades executed
- `winning_trades` (integer) - Number of profitable trades
- `losing_trades` (integer) - Number of losing trades
- `calmar_ratio` (decimal) - Return / max drawdown
- `metadata` (jsonb) - Additional metrics and context (including dashboard snapshot payload; see below)
- `timestamps` - Standard created_at/updated_at

#### Scenario: Daily snapshot creation
- **WHEN** a daily snapshot is created for "Enhanced Congressional" strategy on 2025-12-09
- **THEN** the snapshot SHALL record current equity, P&L, and all calculated metrics
- **AND** the `snapshot_type` SHALL be "daily"
- **AND** the record SHALL be persisted to the database

#### Scenario: Weekly snapshot with full metrics
- **WHEN** a weekly snapshot is generated
- **THEN** the snapshot SHALL include Sharpe ratio calculated from daily returns over the last 52 weeks (or since inception if less)
- **AND** max drawdown SHALL be calculated from peak-to-trough over the measurement period
- **AND** win rate SHALL be calculated as (winning_trades / total_trades) * 100

#### Scenario: Querying snapshots by date range
- **WHEN** querying snapshots between 2025-11-01 and 2025-12-09
- **THEN** the system SHALL return all snapshots within that range ordered by snapshot_date DESC
- **AND** results SHALL be filterable by strategy_name and snapshot_type

---

### Requirement: Dashboard snapshot payload (DB-only UI support)
Performance snapshots SHALL include sufficient account-state data for a read-only HTML dashboard to render **without making Alpaca API calls at request-time**.

At minimum, the system SHALL store the following keys in `performance_snapshots.metadata`:
- `snapshot_captured_at` (ISO8601 timestamp)
- `account`:
  - `cash` (decimal)
  - `invested` (decimal)
  - `cash_pct` (decimal)
  - `invested_pct` (decimal)
  - `position_count` (integer)
- `positions` (array of hashes), each containing:
  - `symbol` (string)
  - `side` (string, e.g. "long"/"short" when known)
  - `qty` (decimal)
  - `market_value` (decimal)
- `top_positions` (array) – top 5 positions by market value
- `risk`:
  - `concentration_pct` (decimal)
  - `concentration_symbol` (string)

#### Scenario: Snapshot includes dashboard payload
- **WHEN** a performance snapshot is created
- **THEN** `metadata.account` SHALL include cash/invested values and percentages
- **AND** `metadata.positions` SHALL be present (may be empty)
- **AND** `metadata.risk.concentration_pct` SHALL be present when positions exist

#### Scenario: Dashboard consumes snapshots without Alpaca calls
- **WHEN** an HTML dashboard request is served using `performance_snapshots` data only
- **THEN** the request handler SHALL NOT call AlpacaService
- **AND** the page renders using the latest stored snapshot data

### Requirement: Performance Metrics Calculation
The system SHALL calculate the following performance metrics using historical trade and equity data:

**Sharpe Ratio**:
- Annualized Sharpe ratio = (Annualized Return - Risk-Free Rate) / Annualized Volatility
- Risk-free rate: Use 4.5% (current T-Bill rate)
- Calculation period: Use all available daily returns (minimum 30 days required)

**Max Drawdown**:
- Calculate peak-to-trough decline as percentage
- Formula: (Trough Value - Peak Value) / Peak Value * 100
- Measurement period: Since inception or specified lookback period

**Win Rate**:
- Formula: (Winning Trades / Total Trades) * 100
- Winning trade: Any trade with positive P&L after fees
- Exclude open positions (closed trades only)

**Volatility**:
- Annualized standard deviation of daily returns
- Formula: StdDev(daily_returns) * sqrt(252)
- Minimum 30 daily returns required

**Calmar Ratio**:
- Formula: Annualized Return / Absolute(Max Drawdown %)
- Higher is better (reward-to-risk metric)

#### Scenario: Sharpe ratio calculation with sufficient data
- **WHEN** calculating Sharpe ratio with 90 days of daily returns
- **AND** annualized return is 12%
- **AND** annualized volatility is 15%
- **AND** risk-free rate is 4.5%
- **THEN** Sharpe ratio SHALL be (0.12 - 0.045) / 0.15 = 0.50

#### Scenario: Insufficient data for metrics
- **WHEN** attempting to calculate Sharpe ratio with only 15 days of data
- **THEN** the system SHALL return nil for Sharpe ratio
- **AND** SHALL log a warning "Insufficient data for Sharpe ratio calculation (minimum 30 days required)"

#### Scenario: Max drawdown calculation
- **WHEN** equity values are [100000, 102000, 98000, 99000, 101000]
- **THEN** peak SHALL be 102000
- **AND** trough SHALL be 98000
- **AND** max drawdown SHALL be -3.92% ((98000-102000)/102000*100)

### Requirement: Strategy Comparison
The system SHALL compare Enhanced Congressional Strategy performance against Simple Momentum Strategy baseline using the following deltas:
- Delta Sharpe Ratio = Enhanced Sharpe - Simple Sharpe
- Delta Max Drawdown = Enhanced Drawdown - Simple Drawdown (more negative is worse)
- Delta Win Rate = Enhanced Win Rate - Simple Win Rate
- Delta Total P&L = Enhanced P&L - Simple P&L
- Delta Annualized Return = Enhanced Return - Simple Return

Comparison SHALL use the same time period for both strategies (aligned by date).

#### Scenario: Enhanced outperforms Simple
- **WHEN** Enhanced strategy has Sharpe ratio 0.8, Simple has 0.5
- **AND** Enhanced has max drawdown -2.5%, Simple has -4.0%
- **AND** Enhanced has win rate 65%, Simple has 55%
- **THEN** delta Sharpe SHALL be +0.3
- **AND** delta drawdown SHALL be +1.5 percentage points (better)
- **AND** delta win rate SHALL be +10 percentage points

#### Scenario: Strategies have different inception dates
- **WHEN** Enhanced strategy started 2025-11-11
- **AND** Simple strategy has data since 2023-10-01
- **THEN** comparison SHALL use overlapping period starting 2025-11-11
- **AND** Simple strategy metrics SHALL be recalculated for that period only

### Requirement: SPY Benchmark Comparison
The system SHALL compare portfolio performance against SPY (S&P 500 ETF) to calculate alpha:
- Fetch SPY daily close prices from Alpaca Market Data API for the same period as portfolio
- Calculate SPY daily returns and annualized return
- Calculate portfolio alpha = Portfolio Annualized Return - SPY Annualized Return
- Calculate beta (portfolio sensitivity to SPY) using covariance and variance
- Store benchmark metrics in snapshot metadata

#### Scenario: Portfolio outperforms SPY
- **WHEN** portfolio annualized return is 15%
- **AND** SPY annualized return is 10%
- **THEN** alpha SHALL be +5%
- **AND** report SHALL indicate "Outperforming SPY by 5.0%"

#### Scenario: SPY data fetching failure
- **WHEN** Alpaca API fails to return SPY historical data
- **THEN** the system SHALL log an error "Failed to fetch SPY benchmark data"
- **AND** SHALL set alpha to nil in the snapshot
- **AND** SHALL continue generating the report with available metrics

#### Scenario: Beta calculation
- **WHEN** portfolio daily returns are [0.01, -0.005, 0.02, -0.01]
- **AND** SPY daily returns are [0.008, -0.003, 0.015, -0.008]
- **THEN** beta SHALL be calculated as Covariance(portfolio, SPY) / Variance(SPY)
- **AND** beta SHALL be stored in snapshot metadata

### Requirement: Weekly Automated Report Generation
The system SHALL automatically generate performance reports every Sunday at 11:00 PM ET via **cron** (no background job runner required).

Accepted invocation mechanisms:
- `bundle exec rake performance:weekly_report` (preferred)
- `./weekly_performance_report.sh` (acceptable)

Actions:
1. Calculate portfolio metrics for the configured `TRADING_MODE` (paper/live)
2. Fetch SPY benchmark data and calculate alpha/beta
3. Create weekly performance snapshot record
4. Save JSON report to `tmp/performance_reports/YYYY-MM-DD-<portfolio>.json`
5. Log summary to Rails logger

#### Scenario: Successful weekly report generation
- **WHEN** the job runs on Sunday 2025-12-15 at 23:00 ET
- **THEN** the system SHALL calculate metrics using data through 2025-12-15
- **AND** SHALL create a performance_snapshot record with snapshot_type="weekly"
- **AND** SHALL save report JSON to `tmp/performance_reports/2025-12-15-blended-portfolio-live.json` (or `...-paper.json`)
- **AND** SHALL log "Weekly performance report generated for 2025-12-15"

#### Scenario: Job failure handling
- **WHEN** the job encounters an error during metric calculation
- **THEN** the system SHALL log the error with full stack trace
- **AND** SHALL NOT create a performance_snapshot record
- **AND** SHALL exit non-zero so cron can alert/notify

#### Scenario: First report with limited data
- **WHEN** generating the first weekly report with only 10 days of trading data
- **THEN** the system SHALL calculate metrics where possible (P&L, win rate)
- **AND** SHALL set Sharpe ratio to nil (insufficient data)
- **AND** SHALL include warning in metadata: "Limited data available (10 days)"

### Requirement: Report Output Format
Performance reports SHALL be saved as JSON files with the following structure:

```json
{
  "report_date": "2025-12-15",
  "report_type": "weekly",
  "period": {
    "start_date": "2025-11-11",
    "end_date": "2025-12-15",
    "trading_days": 24
  },
  "enhanced_strategy": {
    "total_equity": 105432.50,
    "total_pnl": 5432.50,
    "pnl_pct": 5.43,
    "sharpe_ratio": 0.82,
    "max_drawdown_pct": -2.1,
    "volatility": 12.5,
    "win_rate": 68.0,
    "total_trades": 25,
    "winning_trades": 17,
    "losing_trades": 8,
    "calmar_ratio": 2.58
  },
  "simple_strategy": {
    "total_equity": 102100.00,
    "total_pnl": 2100.00,
    "pnl_pct": 2.10,
    "sharpe_ratio": 0.45,
    "max_drawdown_pct": -3.8,
    "volatility": 10.2,
    "win_rate": 55.0,
    "total_trades": 20,
    "winning_trades": 11,
    "losing_trades": 9,
    "calmar_ratio": 0.55
  },
  "comparison": {
    "delta_sharpe": 0.37,
    "delta_drawdown_pct": 1.7,
    "delta_win_rate_pct": 13.0,
    "delta_pnl": 3332.50,
    "delta_return_pct": 3.33
  },
  "benchmark": {
    "spy_return_pct": 8.5,
    "portfolio_alpha_pct": -3.07,
    "portfolio_beta": 0.85,
    "status": "Underperforming SPY by 3.1%"
  },
  "warnings": []
}
```

#### Scenario: Report file creation
- **WHEN** generating a report for 2025-12-15
- **THEN** the file SHALL be saved to `tmp/performance_reports/2025-12-15-blended-portfolio-live.json` (example)
- **AND** the directory SHALL be created if it doesn't exist
- **AND** the file SHALL be valid JSON

#### Scenario: Report with missing Simple strategy data
- **WHEN** Simple strategy has no trades in the period
- **THEN** `simple_strategy` SHALL be null
- **AND** `comparison` SHALL be null
- **AND** warnings SHALL include "No Simple strategy data available for comparison"

### Requirement: Manual Report Generation
The system SHALL provide a command to manually generate performance reports on-demand:
- Command: `GeneratePerformanceReport.call(start_date:, end_date:, strategy_name:)`
- Optional parameters: start_date, end_date (defaults to inception to today)
- Returns: GLCommand result with report hash and file path

#### Scenario: Manual report for date range
- **WHEN** calling `GeneratePerformanceReport.call(start_date: '2025-11-01', end_date: '2025-11-30')`
- **THEN** the system SHALL calculate metrics for November 2025 only
- **AND** SHALL return a GLCommand success result with report data
- **AND** SHALL save report to `tmp/performance_reports/2025-11-30.json`

#### Scenario: Manual report for specific strategy
- **WHEN** calling `GeneratePerformanceReport.call(strategy_name: 'Enhanced Congressional')`
- **THEN** the system SHALL generate a report for Enhanced strategy only
- **AND** SHALL NOT include Simple strategy comparison

### Requirement: Historical Trend Analysis
The system SHALL allow querying historical snapshots to identify trends:
- Query snapshots by strategy and type (daily/weekly)
- Calculate trend metrics: 7-day moving average P&L, 30-day Sharpe trend
- Support export to CSV for external analysis

#### Scenario: Query weekly snapshots for trend
- **WHEN** querying weekly snapshots for "Enhanced Congressional" over last 3 months
- **THEN** the system SHALL return all weekly snapshots ordered chronologically
- **AND** SHALL calculate trend: improving, declining, or stable Sharpe ratio

#### Scenario: Export to CSV
- **WHEN** exporting snapshots to CSV format
- **THEN** the file SHALL include columns: date, strategy, equity, pnl, sharpe, drawdown, win_rate
- **AND** SHALL be saved to `tmp/performance_exports/YYYY-MM-DD.csv`
