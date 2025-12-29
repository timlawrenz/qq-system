# QuiverQuant Trading System (qq-system)

A Ruby on Rails 8 automated trading system that executes multi-strategy portfolios using alternative data sources. The system analyzes congressional trades, corporate insider purchases, and lobbying activity to generate high-conviction trading signals executed through Alpaca Markets.

## Quick Start

### Prerequisites

- Ruby 3.4.5
- PostgreSQL 16 (Docker recommended)
- Bundler 2.6+
- Alpaca Markets API account
- QuiverQuant API subscription (Trader tier or higher)

### Installation

```bash
# Clone repository
git clone <repository-url>
cd qq-system

# Install dependencies
bundle install

# Set up databases (PostgreSQL via Docker on localhost:5432)
bundle exec rails db:setup

# Configure environment variables
cp .env.example .env
# Edit .env with your API keys:
# - ALPACA_API_KEY_ID, ALPACA_API_SECRET_KEY
# - QUIVER_API_TOKEN
```

### Running the System

```bash
# Terminal 1: Start Rails API server
export SECRET_KEY_BASE=$(bundle exec rails secret)
bundle exec rails server
# Server starts at http://localhost:3000
# Health check: http://localhost:3000/up

# Terminal 2: Start background job worker
export SECRET_KEY_BASE=$(bundle exec rails secret)
bin/jobs start

# Rails console (for debugging)
export SECRET_KEY_BASE=$(bundle exec rails secret)
bundle exec rails console
```

## System Architecture

### Modular Design with Packwerk

The system uses **Packwerk** to enforce domain boundaries and prevent tight coupling:

#### Core Packs

- **`packs/trading_strategies`**: Portfolio generation algorithms (congressional, insider, lobbying strategies)
- **`packs/trades`**: Trade management and API endpoints
- **`packs/workflows`**: High-level orchestration (daily trading, rebalancing, data refresh)
- **`packs/alpaca_api`**: Alpaca Markets integration (orders, positions, market data)
- **`packs/data_fetching`**: External data ingestion (QuiverQuant API, historical bars)
- **`packs/performance_analysis`**: Backtest engine and performance metrics
- **`packs/performance_reporting`**: Weekly/monthly performance reports
- **`packs/audit_trail`**: Transaction outbox pattern for reliable event tracking

### Key Technologies

- **Rails 8.0.4**: API-only application
- **SolidQueue**: Background job processing with separate queue database
- **PostgreSQL 16**: Primary data store + dedicated queue database
- **Packwerk**: Enforced domain boundaries
- **GLCommand**: Business logic encapsulation (command pattern)
- **RSpec**: Comprehensive test suite
- **RuboCop**: Code quality and style enforcement

## Daily Operations

### Automated Trading Workflow

The system runs a **multi-strategy automated portfolio** that combines congressional trades, corporate insider purchases, and lobbying activity into a single optimized allocation.

#### Daily Trading Command

```bash
./daily_trading.sh
```

**Workflow Steps:**
1. **Data Refresh**: Fetch latest signals from QuiverQuant API
   - Congressional trades (House & Senate)
   - Corporate insider Form 4 filings
   - Corporate lobbying disclosures
2. **Scoring & Filtering**: Score politicians and insiders based on historical track record
3. **Strategy Generation**: Each enabled strategy generates its target portfolio
4. **Portfolio Blending**: `TradingStrategies::MasterAllocator` combines strategies using weights from `config/portfolio_strategies.yml`
5. **Rebalancing**: Execute trades on Alpaca to align with target portfolio
6. **Audit & Verification**: Log all trades to audit trail and verify positions

**Recommended Schedule**: Daily at 10:00 AM ET (30 minutes after market open)

### Active Trading Strategies

#### 1. Enhanced Congressional Trading Strategy (Primary)

**Weight**: 60-70% of portfolio  
**Command**: `TradingStrategies::GenerateEnhancedCongressionalPortfolio`

**Features:**
- **Committee Oversight Filtering**: Only trade stocks where politician has relevant committee expertise
- **Politician Quality Scoring**: 0-10 scale based on win rate & average return (min threshold: 5.0)
- **Consensus Detection**: Boost positions when multiple politicians buy the same stock (1.3x-2.0x multiplier)
- **Dynamic Position Sizing**: `base_weight × quality_mult × consensus_mult`

**Configuration** (in `daily_trading.sh`):
```ruby
enable_committee_filter: true     # Require relevant oversight
min_quality_score: 5.0           # Minimum politician quality (0-10)
enable_consensus_boost: true     # Boost multi-politician signals
lookback_days: 45                # Signal window (matches disclosure deadline)
```

**Database Schema:**
- `politician_profiles`: Historical performance tracking
- `committees`: 26 congressional committees
- `committee_memberships`: Politician-committee associations
- `industries`: 13 stock industry classifications
- `committee_industry_mappings`: Committee oversight rules

#### 2. Corporate Insider Mimicry Strategy

**Weight**: 20-30% of portfolio  
**Command**: `TradingStrategies::GenerateInsiderMimicryPortfolio`

**Features:**
- Mimics SEC Form 4 insider purchases from executives
- Multiple sizing modes: `value_weighted`, `equal_weight`, `role_weighted`
- Configurable filters: lookback window, minimum transaction value, executive-only
- Default role weights: CEO=2.0, CFO=1.5, Director=1.0

**Data Source**: QuiverQuant `/beta/live/insiders` feed stored in `quiver_trades` table

#### 3. Corporate Lobbying Strategy

**Weight**: 10-20% of portfolio  
**Command**: `TradingStrategies::GenerateLobbyingPortfolio`

**Features:**
- Tracks companies with active federal lobbying efforts
- Hypothesis: Lobbying = regulatory engagement = business momentum
- Filters: minimum spending threshold, recent activity window

**Data Source**: QuiverQuant corporate lobbying data (Lobbying Disclosure Act filings)

### Background Jobs

The SolidQueue worker processes background jobs continuously:

```bash
# Start worker (runs until stopped)
bin/jobs start

# Stop worker gracefully
# Ctrl+C or:
pkill -f "solid_queue"
```

**Key Jobs:**
- `FetchCongressionalTradesJob`: Refresh congressional trading data
- `FetchInsiderTradesJob`: Refresh corporate insider trades
- `ScorePoliticiansJob`: Recalculate politician quality scores (weekly)
- `GenerateWeeklyReportJob`: Performance reporting (weekly)
- `PerformanceAnalysisJob`: Backtest execution (on-demand)

### Testing & Quality Assurance

```bash
# Run full test suite (fast: ~0.9 seconds)
bundle exec rspec

# Run linter (fast: ~2.4 seconds)
bundle exec rubocop

# Run security scanner (fast: ~2.0 seconds)
bundle exec brakeman --no-pager

# Validate package boundaries (fast: ~4.0 seconds)
bundle exec packwerk validate
bundle exec packwerk check

# Compare strategies side-by-side (no real trades)
./test_enhanced_strategy.sh
cat tmp/strategy_comparison_report.json
```

**CI/CD Pipeline**: `.github/workflows/ci.yml` runs all quality checks automatically

## API Endpoints

Business logic is encapsulated in `GLCommand` objects, called by controllers.

### Analysis Endpoints
- `POST /api/v1/analyses`: Start a new performance analysis (backtest)
- `GET /api/v1/analyses/:id`: Retrieve analysis results

### Trade Endpoints
- `POST /api/v1/algorithms/:algorithm_id/trades`: Create trade for algorithm
- `GET /api/v1/trades/:id`: Get specific trade
- `PUT/PATCH /api/v1/trades/:id`: Update trade
- `DELETE /api/v1/trades/:id`: Delete trade

### Health Check
- `GET /up`: Health status (200 = healthy, 500 = error)

## Key Performance Metrics

The backtesting engine calculates:

- **Total P&L**: Absolute profit/loss
- **Annualized Return**: CAGR over backtest period
- **Volatility**: Annualized standard deviation
- **Sharpe Ratio**: Risk-adjusted return
- **Max Drawdown**: Largest peak-to-trough decline
- **Calmar Ratio**: Return / max drawdown
- **Win/Loss Ratio**: Winning trades / losing trades
- **Average Win vs Loss**: Mean profit vs mean loss

## Data Sources

### Alpaca Trading API

**Primary Use**: Trade execution & market data

**Capabilities:**
- Historical market data (bars, quotes)
- Paper trading account (testing)
- Live trading account (production)
- Real-time position tracking
- Order management & execution

**Documentation**: https://alpaca.markets/docs/

### QuiverQuant API (Trader Tier)

**Primary Use**: Alternative data signals  
**Upgraded**: December 10, 2025 (Hobbyist → Trader)

**Core Dataset** (Used in Production):
- Congressional Trading (House & Senate) - 45-day disclosure window

**Tier 2 Datasets** (Available since Dec 10, 2025):
- 🆕 Corporate Insider Trading (SEC Form 4) - 2-day disclosure latency
- 🆕 Government Contracts (federal procurement awards)
- 🆕 Corporate Lobbying (Lobbying Disclosure Act filings)
- 🆕 CNBC Recommendations (media picks)
- 🆕 Institutional Holdings (13F filings)

**API Limits**: 1,000 calls/day  
**Documentation**: https://www.quiverquant.com/

## Database Configuration

### Development Environment

PostgreSQL 16 running via Docker on `localhost:5432`:

```yaml
# config/database.yml
development:
  adapter: postgresql
  database: qq_system_development
  username: postgres
  password: password
  host: localhost

test:
  adapter: postgresql
  database: qq_system_test
  username: postgres
  password: password
  host: localhost

# Separate database for SolidQueue
queue:
  adapter: postgresql
  database: qq_system_queue
  username: postgres
  password: password
  host: localhost
```

### Initial Setup

```bash
# Create all databases
bundle exec rails db:setup

# Run migrations (if needed)
bundle exec rails db:migrate

# Load queue schema (SolidQueue tables)
export SECRET_KEY_BASE=$(bundle exec rails secret)
export DATABASE_URL="postgres://postgres:password@localhost:5432/qq_system_queue"
bundle exec rails runner "load 'db/queue_schema.rb'"
```

## Maintenance & Operations

### Audit Trail Monitoring

The system uses a **transaction outbox pattern** to track all business events:

```bash
# View audit trail statistics
bundle exec rails audit:analyze

# Clean up old audit records (90+ days)
bundle exec rails maintenance:cleanup:audit_trail

# Monitor failures
bundle exec rails runner "puts AuditTrail::FailureAnalysisReport.new.generate"
```

**See**: `docs/operations/audit_trail.md` for detailed queries

### Performance Reports

```bash
# Generate weekly performance report
./weekly_performance_report.sh

# Manual performance check
./manual_performance_check.sh
```

### Database Maintenance

```bash
# Clean up old data (90+ days)
bundle exec rails maintenance:cleanup:all

# Specific cleanups
bundle exec rails maintenance:cleanup:historical_bars
bundle exec rails maintenance:cleanup:audit_trail
bundle exec rails maintenance:cleanup:quiver_trades
```

## Troubleshooting

### Common Issues

**Missing SECRET_KEY_BASE**:
```bash
# Always export before running Rails commands
export SECRET_KEY_BASE=$(bundle exec rails secret)
```

**Database Connection Errors**:
- Verify PostgreSQL Docker container is running on port 5432
- Check credentials: `postgres:password@localhost`

**SolidQueue Worker Fails**:
```bash
# Ensure queue database schema is loaded
export DATABASE_URL="postgres://postgres:password@localhost:5432/qq_system_queue"
bundle exec rails runner "load 'db/queue_schema.rb'"
```

**Tests Failing**:
- All tests should pass in a clean environment
- Run `bundle exec rspec --format documentation` for detailed output

### Performance Expectations

All commands complete quickly (set timeouts to 60+ seconds minimum):

- Bundle install: ~0.4 seconds
- Database setup: ~1.8 seconds
- Database migrations: ~1.7 seconds
- Test suite: ~0.9 seconds (4 examples)
- RuboCop linting: ~2.4 seconds
- Brakeman security scan: ~2.0 seconds
- Packwerk checks: ~4.0 seconds

**NEVER CANCEL** any of these commands - they complete quickly but need adequate timeout buffer.

## Documentation

### Strategy Documentation
- [`DAILY_TRADING.md`](DAILY_TRADING.md) - Daily trading process
- [`ENHANCED_STRATEGY_MIGRATION.md`](ENHANCED_STRATEGY_MIGRATION.md) - Enhanced congressional strategy
- [`docs/strategy/INSIDER_TRADING_STRATEGY.md`](docs/strategy/INSIDER_TRADING_STRATEGY.md) - Corporate insider strategy
- [`docs/strategy/strategic-framework-with-alternative-data.md`](docs/strategy/strategic-framework-with-alternative-data.md) - Strategic framework

### Operations Documentation
- [`docs/operations/audit_trail.md`](docs/operations/audit_trail.md) - Audit trail system
- [`docs/operations/QUIVER_TRADER_UPGRADE.md`](docs/operations/QUIVER_TRADER_UPGRADE.md) - QuiverQuant tier upgrade
- [`docs/operations/INTEGRATING_INSIDER_STRATEGY.md`](docs/operations/INTEGRATING_INSIDER_STRATEGY.md) - Insider strategy integration

### Testing Documentation
- [`docs/testing/QUICKSTART_TESTING.md`](docs/testing/QUICKSTART_TESTING.md) - Testing guide
- [`TESTING_COMPLETE.md`](TESTING_COMPLETE.md) - Testing completion report

### Development Documentation
- [`CONVENTIONS.md`](CONVENTIONS.md) - Code conventions
- [`AGENTS.md`](AGENTS.md) - AI agent instructions
- [`docs/audit_trail_queries.md`](docs/audit_trail_queries.md) - Audit trail queries

## Development Workflow

### Pre-Commit Checklist

```bash
# 1. Run full test suite
bundle exec rspec

# 2. Run linter
bundle exec rubocop

# 3. Run security scanner
bundle exec brakeman --no-pager

# 4. Validate package boundaries
bundle exec packwerk validate
bundle exec packwerk check

# 5. Manual validation (optional but recommended)
export SECRET_KEY_BASE=$(bundle exec rails secret)
bundle exec rails server  # Test /up endpoint
curl -s http://localhost:3000/up
```

### Making Changes

1. **Understand domain boundaries**: Check `packwerk.yml` and package dependencies
2. **Follow conventions**: See `CONVENTIONS.md` for coding standards
3. **Write tests first**: Unit tests for GLCommands, request specs for controllers
4. **Run validations**: Never skip the pre-commit checklist
5. **Update documentation**: Keep README and relevant docs in sync

### Repository Structure

```
├── app/                    # Rails application code
│   ├── controllers/        # API controllers
│   ├── models/            # ActiveRecord models
│   └── jobs/              # Background jobs
├── packs/                 # Packwerk domains
│   ├── alpaca_api/        # Alpaca integration
│   ├── audit_trail/       # Event tracking
│   ├── data_fetching/     # External data
│   ├── performance_analysis/  # Backtest engine
│   ├── performance_reporting/ # Reports
│   ├── trades/            # Trade management
│   ├── trading_strategies/    # Strategy algorithms
│   └── workflows/         # High-level orchestration
├── spec/                  # RSpec tests
├── config/                # Rails configuration
│   ├── database.yml       # Database config
│   ├── routes.rb          # API routes
│   └── portfolio_strategies.yml  # Strategy weights
├── db/                    # Database files
│   ├── schema.rb          # Main schema
│   ├── queue_schema.rb    # SolidQueue schema
│   └── seeds.rb           # Seed data
├── docs/                  # Documentation
├── lib/                   # Custom libraries
│   └── tasks/             # Rake tasks
└── openspec/              # Change proposals
```

## License

See [LICENSE](LICENSE) file for details.

## Support

For questions or issues, please refer to the documentation in `docs/` or create an issue in the repository.

---

**Note**: This is a live trading system. Always test changes thoroughly in paper trading mode before deploying to production.
