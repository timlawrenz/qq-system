# Project Context

## Purpose
QuiverQuant (qq-system) is a Ruby on Rails API-only application designed for automated trading performance analysis. The system analyzes historical trading strategy performance by processing trades against market data from the Alpaca API. The core functionality answers: **"How well did my algorithm perform over a specific period?"**

### Key Features
- Performance analysis engine for trading strategies with comprehensive metrics (Sharpe Ratio, Max Drawdown, P&L, Calmar Ratio, Win/Loss Ratio)
- Historical market data caching from Alpaca API for efficient analysis
- Automated trading bot based on congressional trade signals (Simple Momentum Strategy)
- Backtesting framework with configurable holding periods and exit strategies
- Background job processing for asynchronous analysis

## Tech Stack

### Core Framework
- **Ruby**: 3.4.5
- **Rails**: 8.0.2.1 (API-only mode using `ActionController::API`)
- **Application Type**: Pure API backend (no views/assets)

### Database
- **Engine**: PostgreSQL 16 (runs via Docker container)
- **Connection**: localhost:5432
- **Credentials**: Username: `postgres`, Password: `password`
- **Databases**:
  - Development: `qq_system_development`
  - Test: `qq_system_test`
  - Queue: `qq_system_queue` (dedicated database for SolidQueue)

### Job Processing
- **Queue**: SolidQueue v1.2+ with dedicated database
- **Worker**: `bin/jobs` executable for background job processing
- **Scheduling**: Manual execution initially, automated scheduling planned (whenever gem or SolidQueue recurring jobs)

### Code Organization & Architecture
- **Modularization**: Packwerk for enforcing domain boundaries
- **Command Pattern**: GLCommand gem (https://github.com/givelively/gl_command) for business logic
- **State Machines**: state_machines-activerecord for state transitions
- **Pack Structure**: 5 domain packs in `packs/` directory:
  - `alpaca_api` - Alpaca Trade API interactions
  - `data_fetching` - External data fetching and caching
  - `performance_analysis` - Core analysis engine
  - `trades` - Trade management and execution
  - `trading_strategies` - Strategy definitions and logic

### Testing
- **Framework**: RSpec with Rails integration
- **API Mocking**: VCR for recording/replaying HTTP interactions
- **Test Data**: FactoryBot for fixtures (no short notation, use `FactoryBot.create`)
- **N+1 Detection**: n_plus_one_control gem for query optimization tests
- **Coverage**: 350+ examples, 0 failures (as of 2025-11-04)
- **VCR Cassettes**: Stored in `spec/fixtures/vcr_cassettes/`

### Code Quality Tools
- **Linting**: RuboCop with custom configuration
- **Security**: Brakeman for vulnerability scanning
- **Dependencies**: Packwerk for boundary enforcement
- **Pre-commit**: `bin/rspec --fail-fast && bin/packwerk check && bin/packwerk validate && bin/rubocop --fail-fast`

### External APIs
- **Alpaca Market Data API**: Historical OHLCV bar data
- **Alpaca Trading API**: Order execution, position management, account data
  - Gem: `alpaca-trade-api` for Ruby SDK
  - Service: `AlpacaService` wrapper in `packs/alpaca_api/`
- **Quiver Quantitative API**: Congressional trading signals
  - Client: `QuiverClient` in `packs/data_fetching/`
  - Endpoint: https://api.quiverquant.com

### Key Gems
- **faraday**: HTTP client for external API calls
- **connection_pool**: Connection pooling for thread safety
- **bcrypt**: Password hashing (planned auth)
- **puma**: Application server
- **bootsnap**: Boot time optimization
- **sentry-rails/sentry-ruby**: Error tracking and monitoring

### Future/Planned
- **Authorization**: Pundit (not yet implemented)
- **UI Components**: Tailwind CSS v4 + ViewComponent (for future dashboard)
- **Monitoring**: Structured logging, alerting to Slack/email

## Project Conventions

### Code Style
- **Command Naming**: All `GLCommand` class names must start with a verb (e.g., `SendEmail`, `CreateUser`, `GenerateTargetPortfolio`)
- **Status Fields**: Use string type for status columns managed by `state_machines-activerecord` gem
- **Testing Notation**: Use `FactoryBot.create` (NOT short notation like `create`)
- **Comments**: Only comment code that needs clarification; avoid over-commenting
- **Pre-commit Command**: `bin/rspec --fail-fast && bin/packwerk check && bin/packwerk validate && bin/rubocop --fail-fast`

### Architecture Patterns
- **Controller Responsibilities**: Focus on auth (Pundit), input validation, calling GLCommand, handling results
  - NO domain logic in controllers
  - Controllers should be thin, delegating to commands
- **Business Logic**: Use `GLCommand` gem (https://github.com/givelively/gl_command) for complex operations
  - **Naming Convention**: Command class names MUST start with a verb (e.g., `SendEmail`, `CreateUser`, `GenerateTargetPortfolio`, `FetchQuiverData`)
  - **Single Responsibility**: Each command has a small, focused purpose
  - **Chaining**: Combine commands for multi-step operations
  - **Rollback Support**: Commands can implement `rollback` method for automatic transactional rollback on failure
  - **RSpec Matchers**: GLCommand provides declarative matchers (https://github.com/givelively/gl_command#rspec-matchers)
  - **Context Stubbing**: Use `build_context` method for testing command responses
- **State Management**: Use `state_machines-activerecord` for state transitions
  - Status columns MUST be string type
  - Example: Analysis model transitions: `pending` → `in_progress` → `completed` / `failed`
- **Packwerk Organization**: Code organized into domain-specific packs in `packs/` directory:
  - `packs/alpaca_api` - Alpaca Trade API service wrapper
  - `packs/trading_strategies` - Algorithm model, strategy logic, ExecuteSimpleStrategyJob
  - `packs/trades` - Trade model, CRUD commands, RebalanceToTarget, AlpacaOrder model
  - `packs/data_fetching` - HistoricalBar cache, QuiverTrade model, AlpacaApiClient, QuiverClient
  - `packs/performance_analysis` - Analysis model, performance calculation engine, AnalysePerformanceJob
- **Service Pattern**: External API interactions wrapped in dedicated service classes
  - `AlpacaService` - Wraps alpaca-trade-api gem for orders, positions, account equity
  - `QuiverClient` - HTTP client for congressional trade data
  - `AlpacaApiClient` - HTTP client for market data (historical bars)
- **ViewComponents**: Reusable UI components in `app/components/` with preview files in `spec/components/previews/`
  - Documentation: https://viewcomponent.org/
  - Required for all UI elements when dashboard is built

### Testing Strategy
- **NO Controller Specs**: Never write controller specs - use request specs instead
- **Isolated Unit Tests**: Cover classes, methods, and GLCommands with mocks for DB/external calls
  - Use GLCommand RSpec matchers for declarative testing (https://github.com/givelively/gl_command#rspec-matchers)
  - Always test rollback logic for commands that implement it
  - Use `build_context` method for stubbing command responses in tests
  - Example: `let(:context) { GenerateTargetPortfolio.build_context(target_positions: positions) }`
- **Request Specs**: Test auth (Pundit) and HTTP responses; verify correct GLCommand is called with correct args
  - Primary use: Validate authentication/authorization
  - Secondary use: Ensure controllers call the right command with right parameters
  - Example location: `spec/requests/`
- **No Mocks in Request/Integration Specs**: Integration and request specs should hit real database
  - These are full-stack tests validating end-to-end behavior
  - Use FactoryBot to set up test data
- **Limited Integration Tests**: Only for critical end-to-end business flows
  - Example: Performance analysis workflow (API call → job → metrics calculation)
  - Example: Trading execution workflow (signal generation → order placement)
- **N+1 Query Prevention**: Use `n_plus_one_control` gem for data-fetching tests
  - Critical for API endpoints returning collections
  - Enforce eager loading in queries
- **VCR for API Mocking**: Record and replay real API interactions for external service specs
  - Cassettes stored in `spec/fixtures/vcr_cassettes/`
  - Naming convention: `{service_name}/{test_scenario}.yml`
  - Examples: `alpaca_service/aapl_bars.yml`, `quiver_client/successful_response.yml`
  - Some VCR specs temporarily disabled (15 pending as of 2025-11-04)
- **FactoryBot**: Define factories in `spec/factories/` following naming conventions
  - MUST use explicit notation: `FactoryBot.create(:user)` NOT `create(:user)`
  - Factory files named after model: `user.rb`, `trade.rb`, `analysis.rb`
  - Use traits for variations: `FactoryBot.create(:trade, :purchase)` vs `FactoryBot.create(:trade, :sale)`
- **Test Data Cleanup**: Use database_cleaner or RSpec's transactional fixtures
  - Each test should be isolated and repeatable

### Git Workflow
- CI/CD Pipeline runs:
  1. Security scan: `bin/brakeman --no-pager`
  2. Linting: `bin/rubocop -c .rubocop.yml`
  3. Dependency validation: `bin/packwerk validate && bin/packwerk check`
  4. Test suite: `bundle exec rspec`
- Always run these locally before committing
- All commands complete quickly (<5 seconds); never cancel them

## Domain Context

### Data Models
- **Algorithm**: Trading strategies (name, description)
- **Trade**: Individual trade records (symbol, side, quantity, price, executed_at)
- **Analysis**: Performance analysis results with JSONB metrics (start_date, end_date, status, results)
- **HistoricalBar**: Cached market data from Alpaca API (symbol, timestamp, OHLCV data)
- **QuiverTrade**: Congressional trading data from Quiver API (ticker, trader_name, transaction_date, transaction_type)
- **AlpacaOrder**: Logs of orders placed with Alpaca API (alpaca_order_id, symbol, side, status, filled_avg_price)

### Core Workflows

#### Performance Analysis
1. Submit trades via API endpoint
2. Create Analysis record with `pending` status, queue background job
3. Background job fetches/caches missing historical data from Alpaca
4. Calculate daily portfolio value time series from trades
5. Generate performance metrics (Sharpe, drawdown, P&L, etc.)
6. Store results in Analysis JSONB column, update status to `completed`

#### Automated Trading (Simple Momentum Strategy)
**Current Implementation (MISSING DATA FETCH STEP):**
1. ❌ **Missing**: Daily job to fetch congressional trades from Quiver API and save to QuiverTrade table
2. ✅ `ExecuteSimpleStrategyJob` queries QuiverTrade for congressional purchases in last 45 days
3. ✅ Generate equal-weight target portfolio from unique tickers
4. ✅ Fetch current Alpaca account positions
5. ✅ Execute sells first (for removed positions), then buys (for new/adjusted positions)
6. ✅ Log all orders in AlpacaOrder table

**Complete Workflow (After FetchQuiverData Implementation):**
1. **8:00 AM ET**: `FetchQuiverDataJob` runs → fetches congressional trades → saves to QuiverTrade table
2. **9:45 AM ET**: `ExecuteSimpleStrategyJob` runs → reads QuiverTrade → generates signals → executes trades

**Data Contract (Strategy ↔ Execution):**
- Strategy generates array of `TargetPosition` objects (symbol, asset_type, target_value)
- `RebalanceToTarget` command consumes TargetPosition[] and executes trades
- This separation allows easy addition of new strategies without changing execution logic

**Trading Execution Details:**
- Sells executed first to free up capital
- Buys executed using notional (dollar amount) orders
- All orders logged in `AlpacaOrder` table for audit trail
- Uses Alpaca's market orders for immediate execution
- Idempotent design: safe to retry jobs

### Key Metrics Calculated
- Total Profit/Loss (absolute and percentage)
- Annualized Return
- Volatility (annualized standard deviation)
- Sharpe Ratio (risk-adjusted return)
- Max Drawdown (maximum peak-to-trough decline)
- Calmar Ratio (return vs. max drawdown)
- Win/Loss Ratio
- Average Win vs. Average Loss

### Implemented Strategies
- **Simple Momentum Strategy**: Equal-weight portfolio based on congressional purchases in last 45 days
  - Backtest Results (2023-2025): 2.77% return, 3.1 win/loss ratio, 1.27% max drawdown, -1.26 Sharpe
  - Characterized as low-risk, low-return with high win rate
- **Time-Based Exit**: 90-day holding period for positions

## Important Constraints
- **Financial Data Accuracy**: This is a financial trading system - accuracy and reliability are CRITICAL
  - All monetary calculations use BigDecimal, never Float
  - Validate data integrity at every step
  - Comprehensive error logging for debugging
- **API Rate Limits**: 
  - Alpaca API has rate limits; caching layer in HistoricalBar table is essential
  - QuiverQuant API: 60 requests/minute (enforced in QuiverClient)
  - Implement exponential backoff for retries
- **Idempotent Design**: All API interactions must be idempotent
  - Safe to retry failed jobs
  - Use find_or_initialize_by for data persistence
  - Deduplicate on composite keys (e.g., ticker + trader + transaction_date)
- **Database Setup**: Requires PostgreSQL via Docker on localhost:5432
  - Username: `postgres`, Password: `password`
  - Must create 3 databases: `_development`, `_test`, `_queue`
  - Schema migrations managed via Rails migrations
- **Environment Variables**: Always export SECRET_KEY_BASE before Rails commands
  - Command: `export SECRET_KEY_BASE=$(bundle exec rails secret)`
  - Required for: server, console, migrations, jobs
  - Auto-generated credentials at `config/credentials/development.yml.enc`
- **Migration Constraints**: 
  - Migrations MUST only contain schema changes
  - Use separate Rake tasks for data backfills/manipulation
  - Never put business logic in migrations
- **Safe Deployments**: Follow multi-phase deployment process for column changes
  - **Phase 1**: Add new column (nullable)
  - **Phase 2**: Deploy code that writes to both old and new columns
  - **Phase 3**: Backfill existing data via Rake task
  - **Phase 4**: Add NOT NULL constraint if needed
  - **Phase 5**: Deploy code that reads from new column
  - **Phase 6**: Remove old column
- **Command Execution**: All commands complete quickly (<5 seconds typical)
  - Set timeouts to 60+ seconds to ensure completion
  - **NEVER CANCEL** commands mid-execution
  - Commands are designed to be fast, timeouts are safety buffer
- **Testing Before Commit**: Always run full suite before pushing
  - Command: `bin/rspec --fail-fast && bin/packwerk check && bin/packwerk validate && bin/rubocop --fail-fast`
  - All checks typically complete in under 15 seconds total
  - CI/CD will run same checks; don't rely on it to catch issues

## External Dependencies

### Alpaca Market Data API
- **Purpose**: Historical price data (OHLCV bars) and real-time trading
- **Caching**: All historical data cached in `HistoricalBar` table to minimize API calls
- **Service Wrapper**: `AlpacaService` in `packs/trades/app/services/`
- **Authentication**: API keys stored in Rails credentials

### Alpaca Trading API
- **Purpose**: Execute buy/sell orders, retrieve account positions and equity
- **Gem**: `alpaca-trade-api-ruby`
- **Service Methods**: `account_equity()`, `current_positions()`, `place_order()`

### Quiver Quantitative API
- **Purpose**: Congressional trading data for signal generation
- **Client**: `QuiverClient` in `packs/data_fetching/app/services/`
- **Data Model**: `QuiverTrade` stores fetched congressional trade records

## Performance Expectations

All commands complete quickly; set generous timeouts (60+ seconds) but **NEVER CANCEL**:

| Command | Expected Time | Notes |
|---------|--------------|-------|
| `bundle install` | ~0.4s | Gems cached after first install |
| `bundle exec rails db:setup` | ~1.8s | Creates and seeds databases |
| `bundle exec rails db:migrate` | ~1.7s | Runs pending migrations |
| `bundle exec rspec` | ~0.9s | 350 examples, 0 failures |
| `bundle exec rubocop` | ~2.4s | No offenses detected |
| `bundle exec brakeman --no-pager` | ~2.0s | No security warnings |
| `bundle exec packwerk check` | ~4.0s | Validates dependencies |
| `bundle exec packwerk validate` | ~2.8s | Validates configuration |
| `bundle exec rails server` | ~2-3s | Server ready to accept connections |
| `bundle exec rails console` | ~1-2s | Interactive console ready |

**Total pre-commit time**: ~15 seconds for all checks

**Why set 60+ second timeouts?**
- Ensures commands complete even if system is under load
- Prevents accidental cancellation of working commands
- Commands are designed to be fast; timeout is safety buffer
- Better to wait a few extra seconds than corrupt state

**CI/CD Pipeline**: Runs same commands with same expectations

## API Endpoints
- `POST /api/v1/analyses` - Initiate performance analysis
- `GET /api/v1/analyses/:id` - Retrieve analysis status/results
- `POST /api/v1/algorithms/:algorithm_id/trades` - Create trade
- `GET /api/v1/trades/:id` - Retrieve trade
- `PUT/PATCH /api/v1/trades/:id` - Update trade
- `DELETE /api/v1/trades/:id` - Delete trade
- `GET /up` - Health check endpoint (returns green HTML page)

**API Design Principles:**
- JSON API format for all endpoints
- RESTful routing conventions
- Controllers are thin, delegate to GLCommands
- Consistent error response format
- Rate limiting planned but not yet implemented

**Authentication/Authorization:**
- Currently NONE (planned: Pundit for authorization)
- Future: API token authentication for external clients
- Future: Role-based access control (RBAC) for different user types

## Current Status & Roadmap

### ✅ Production-Ready Components
- Performance analysis engine with comprehensive metrics
- Historical data caching from Alpaca API
- Trade CRUD operations with API endpoints
- Simple Momentum strategy (backtested)
- Execution engine (RebalanceToTarget)
- Background job processing (SolidQueue)
- Comprehensive test coverage (350 examples)

### 🚧 In Development
- **FetchQuiverData command** (Critical - blocks paper trading)
- **FetchQuiverDataJob** (Critical - blocks paper trading)
- Strategy framework (BaseStrategy, CompareStrategies)
- Strategy configuration system (YAML-based)

### 📋 Planned Features
- Forward testing infrastructure
- Multiple strategy implementations (exit logic, position sizing)
- Web dashboard for monitoring (Tailwind CSS + ViewComponent)
- Automated scheduling (whenever gem or SolidQueue recurring jobs)
- Enhanced monitoring & alerting (Slack, email)
- API authentication & authorization (Pundit)

### 🎯 Next Milestone: Paper Trading
**Blocker**: FetchQuiverData implementation (4-6 hours)
**Timeline**: Can start paper trading within 24 hours of implementation
**Goal**: Validate system works end-to-end with real market data

## Development Workflow

### Local Setup
```bash
# 1. Install dependencies
bundle install

# 2. Setup databases (creates dev/test/queue databases)
bundle exec rails db:setup

# 3. Set environment variable
export SECRET_KEY_BASE=$(bundle exec rails secret)

# 4. Start server
bundle exec rails server

# 5. Start background jobs (separate terminal)
bin/jobs

# 6. Test health
curl http://localhost:3000/up
```

### Running Tests
```bash
# Full test suite
bundle exec rspec

# Single file
bundle exec rspec spec/models/trade_spec.rb

# Single test
bundle exec rspec spec/models/trade_spec.rb:45

# With coverage
COVERAGE=true bundle exec rspec
```

### Quality Checks
```bash
# Pre-commit checks (run all)
bin/rspec --fail-fast && bin/packwerk check && bin/packwerk validate && bin/rubocop --fail-fast

# Individual checks
bin/rubocop                    # Linting
bin/brakeman --no-pager        # Security
bin/packwerk check             # Dependencies
bin/packwerk validate          # Configuration
```

### Console & Debugging
```bash
# Rails console
export SECRET_KEY_BASE=$(bundle exec rails secret) && bundle exec rails console

# Test a command
result = FetchQuiverData.call(start_date: 30.days.ago.to_date)
puts result.inspect

# Test a job
ExecuteSimpleStrategyJob.perform_now

# Check database
QuiverTrade.count
AlpacaOrder.last(5)
```

## Troubleshooting

### Common Issues

**"SECRET_KEY_BASE missing"**
```bash
export SECRET_KEY_BASE=$(bundle exec rails secret)
```

**"Database does not exist"**
```bash
bundle exec rails db:create
bundle exec rails db:migrate
```

**"SolidQueue relation does not exist"**
```bash
# Load queue schema
export DATABASE_URL="postgres://postgres:password@localhost:5432/qq_system_queue"
bundle exec rails runner "load 'db/queue_schema.rb'"
```

**"PostgreSQL connection refused"**
- Ensure PostgreSQL Docker container is running on port 5432
- Check credentials: postgres/password
- Verify host is localhost (not 127.0.0.1)

**"VCR cassette not found"**
- Run tests to record new cassettes
- Check `spec/fixtures/vcr_cassettes/` for existing cassettes
- Some VCR specs temporarily disabled (use `xdescribe` or `xcontext`)

**"Packwerk violations"**
- Review `packwerk.yml` and `package.yml` files
- Ensure dependencies are declared correctly
- Some circular dependencies are intentional (e.g., trades ↔ trading_strategies)
