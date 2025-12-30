# Change: Add Performance Dashboard for Live Trading

## Why

Now that the system is running live trading with real money (limited to user's risk tolerance), we need visibility into performance metrics to:
- Track live Sharpe ratio, max drawdown, and win rate in real-time
- Compare Enhanced Congressional Strategy performance against Simple Strategy baseline
- Benchmark results against SPY (S&P 500 ETF) to measure alpha generation
- Generate automated weekly performance reports for quick health checks
- Make data-driven decisions about strategy parameters and risk management

Currently, there is no automated way to calculate or visualize these metrics. Performance data exists in the database (trades, positions, account equity) but requires manual Rails console queries to extract.

## What Changes

- **NEW Capability**: `performance-reporting` - Track and report live trading performance
  - Calculate key metrics: Sharpe ratio, max drawdown, win rate, total P&L, volatility
  - (Future) Attribute results to component strategies (today: portfolio-only metrics)
  - Benchmark against SPY ETF performance
  - Generate weekly automated reports (text/JSON format)
  - Store historical snapshots for trend analysis
  - **Provide DB-backed “account snapshot” fields** usable by a future HTML dashboard without triggering Alpaca calls at request-time
- **Database**: Add `performance_snapshots` table to track daily/weekly metrics
- **Scheduled execution (cron)**: run weekly (Sunday night) via `rake performance:weekly_report` (no background job runner required)
- **Command**: `GeneratePerformanceReport` command to calculate all metrics
- **Service**: `PerformanceCalculator` for metric computations (Sharpe, drawdown, etc.)
- **Service**: `BenchmarkComparator` to fetch SPY data and calculate relative performance
- **Output**: Weekly report saved to `tmp/performance_reports/YYYY-MM-DD-<portfolio>.json` and optionally logged

### Scope
- ✅ Metrics: Sharpe ratio, max drawdown, win rate, total P&L, volatility, Calmar ratio
- ✅ Comparisons: portfolio vs SPY (alpha/beta)
- ❌ NOT included (yet): per-component-strategy performance attribution
- ✅ Weekly automation via cron (no SolidQueue required)
- ✅ Historical snapshots for trend tracking
- ✅ Snapshot payload includes DB-stored account/positions fields for read-only UI consumption
- ❌ NOT included: Email/Slack notifications (future enhancement)
- ❌ NOT included: Web dashboard UI (future enhancement)
- ❌ NOT included: Intraday metrics (daily close only)

## Impact

### Affected Capabilities
- **NEW**: `performance-reporting` (full spec in delta)

### Affected Code
- **New Pack**: Create `packs/performance_reporting/` with:
  - `app/models/performance_snapshot.rb` - Daily/weekly metrics storage
  - `app/commands/generate_performance_report.rb` - Main command
  - `app/services/performance_calculator.rb` - Metric calculations
  - `app/services/benchmark_comparator.rb` - SPY comparison logic
  - `app/jobs/generate_performance_report_job.rb` - Optional weekly automation (if a job runner is enabled later)
- **Snapshot payload extension** (no new table required):
  - Store dashboard-oriented account state in `performance_snapshots.metadata` (cash/invested breakdown, positions list, and derived risk fields)
- **Database Migration**: `create_performance_snapshots`
- **Dependencies**:
  - Uses existing `AlpacaService` to fetch account equity and SPY historical data
  - Reads existing `AlpacaOrder` and `AlpacaPosition` models
  - No external API dependencies beyond existing Alpaca integration

### Breaking Changes
- **NONE** - This is purely additive

### Effort Estimate
- **Database**: 1 migration (30 min)
- **Models**: 1 model (30 min)
- **Services**: 2 services (4 hours)
- **Command**: 1 command (2 hours)
- **Job**: 1 background job (1 hour)
- **Tests**: Unit + integration tests (4 hours)
- **Total**: ~12 hours (~1.5 days)

### Risk Assessment
- **Low Risk**: No changes to existing trading logic
- **Data Quality**: Dependent on accurate historical data from Alpaca (already in use)
- **Performance**: Calculations run once weekly, negligible impact

### Success Criteria
1. Weekly reports automatically generated every Sunday night
2. Reports contain all key metrics (Sharpe, drawdown, win rate, P&L)
3. Enhanced vs Simple strategy comparison shows accurate deltas
4. SPY benchmark comparison calculates alpha correctly
5. Historical snapshots stored and queryable for trends
