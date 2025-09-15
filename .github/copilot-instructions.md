# qq-system

qq-system is a Ruby on Rails 8.0 API application built for performance analysis of algorithmic trading strategies. It integrates with the Alpaca Markets API to fetch historical data and calculate comprehensive trading performance metrics like Sharpe ratio, max drawdown, and risk-adjusted returns.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Prerequisites and Dependencies
- Install Ruby 3.4.5 (required version per `.ruby-version`)
  - `git clone https://github.com/rbenv/rbenv.git ~/.rbenv`
  - `git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build`
  - `export PATH="$HOME/.rbenv/bin:$PATH" && eval "$(rbenv init -)"`
  - `rbenv install 3.4.5` -- takes 15-20 minutes on most systems. NEVER CANCEL. Set timeout to 45+ minutes.
  - `rbenv global 3.4.5`
- Install PostgreSQL:
  - `sudo apt-get update && sudo apt-get install -y postgresql postgresql-contrib libpq-dev`
- Install system dependencies:
  - `sudo apt-get install -y build-essential git libssl-dev libreadline-dev zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev libyaml-dev`

### Bootstrap, Build, and Test the Repository
- Clone and bootstrap:
  - `git clone [repo-url] && cd qq-system`
  - `gem install bundler --conservative`
  - `bundle install` -- takes 3-5 minutes. NEVER CANCEL. Set timeout to 15+ minutes.
- Database setup:
  - `bin/rails db:prepare` -- sets up development and test databases. Takes 1-2 minutes.
- Asset compilation (for production-like testing):
  - `bundle exec rails assets:precompile` -- compiles assets. Takes 1-2 minutes.
- Run tests:
  - `bundle exec rspec` -- takes 5-10 minutes for full test suite. NEVER CANCEL. Set timeout to 30+ minutes.
  - Tests include unit tests for GLCommands, request specs for API endpoints, and integration tests for critical trading analysis flows
- Lint and security checks:
  - `bin/rubocop` -- Ruby code style. Takes 30-60 seconds.
  - `bundle exec packwerk validate` -- validates Packwerk configuration. Takes 10-20 seconds.
  - `bundle exec packwerk check` -- checks pack dependencies. Takes 30-60 seconds.
  - `bin/brakeman --no-pager` -- Rails security scanner. Takes 1-2 minutes.
  - `bin/importmap audit` -- JavaScript dependency security scan. Takes 10-30 seconds.

### Development Server
- Start the Rails API server:
  - ALWAYS run the bootstrapping steps first.
  - `bin/rails server` or `bin/rails s` -- starts on port 3000
  - API endpoints available at `http://localhost:3000/api/v1/`
- Background job processing (if Sidekiq is configured):
  - `bundle exec sidekiq` -- starts background job worker

### Database Operations
- Reset database: `bin/rails db:reset` -- drops, creates, loads schema, and seeds. Takes 30-60 seconds.
- Run migrations: `bin/rails db:migrate`
- Create migration: `bin/rails generate migration [MigrationName]`
- Database console: `bin/rails dbconsole`

## Validation

### Always Run Complete Validation Scenarios
- **CRITICAL**: After any changes to trading logic, ALWAYS run full test suite and validate with sample data.
- API Testing: Use curl or Postman to test key endpoints:
  - `POST /api/v1/analyses` - Submit trading data for analysis (creates Analysis with pending status)
  - `GET /api/v1/analyses/:id` - Retrieve analysis results (status: pending/running/completed/failed)
  - `POST /api/v1/algorithms/:id/trades` - Submit individual trades
  - `GET /api/v1/trades/:id` - Retrieve specific trade data
  - `PUT/PATCH /api/v1/trades/:id` - Update trade information
  - `DELETE /api/v1/trades/:id` - Remove trade from algorithm
- Performance Analysis Validation: When modifying calculation logic, verify with known test datasets that metrics like Sharpe ratio, max drawdown, Calmar ratio, and win/loss ratios are calculated correctly. Key metrics include:
  - Total P&L (absolute and percentage)
  - Annualized return and volatility
  - Sharpe ratio (risk-adjusted return)
  - Max drawdown (peak-to-trough loss)
  - Win/loss ratio and average win vs average loss
- Database Integrity: Always run `bin/rails db:check` after migrations.

### Pre-commit Requirements
- ALWAYS run these commands before committing or the CI (.github/workflows/ci.yml) will fail:
  - `bin/rubocop` -- fix any style violations
  - `bundle exec rspec` -- all tests must pass
  - `bundle exec packwerk validate && bundle exec packwerk check` -- Packwerk architecture validation
  - `bin/brakeman --no-pager` -- security scan must pass
  - `bin/importmap audit` -- JavaScript security scan must pass

## Architecture and Conventions

### Development Philosophy (see CONVENTIONS.md)
- **GLCommand Pattern**: Use `GLCommand` gem for all business logic. Commands must start with verbs (e.g., `CalculatePerformanceMetrics`, `FetchHistoricalData`).
- **Packwerk Architecture**: Organize code into domain packs. New logic should go in appropriate packs (trading, analysis, data_fetching).
- **ViewComponents**: Use ViewComponents for any UI elements (located in `app/components`).
- **Testing Strategy**: 
  - NO controller specs
  - Isolated unit tests for GLCommands (including rollback logic)
  - Request specs for auth and API behavior validation
  - Limited integration tests for critical end-to-end flows
  - N+1 query prevention tests using `n_plus_one_control`

### Key Domain Areas
- **Trading Analysis Engine**: Core business logic for calculating performance metrics (see `docs/02-analysis.md`)
- **Alpaca Integration**: Historical market data fetching and caching (HistoricalBar model)
- **API Layer**: RESTful endpoints for submitting and retrieving analysis results
- **Data Models**: Algorithm, Trade, Analysis, HistoricalBar entities (see `docs/01-initial-setup.md`)
- **Background Jobs**: Use Sidekiq for asynchronous analysis processing (RunAnalysisJob)

### Critical Files and Locations
- Main application code: `app/` (controllers, models, jobs, mailers)
- Business logic commands: Look for GLCommand classes throughout the app
- API routes: `config/routes.rb`
- Database schema: `db/schema.rb`
- Migrations: `db/migrate/`
- Documentation: `docs/` contains domain-specific analysis documentation
- Configuration: `config/` directory for Rails configuration
- Tests: Standard Rails test structure (when created)

## Common Tasks

### Adding New Trading Analysis Features
1. Create GLCommand classes for business logic (e.g., `CalculatePerformanceMetrics`, `FetchHistoricalData`)
2. Use service objects like `Alpaca::DataFetcher` and `Performance::Calculator` 
3. Add API endpoints in appropriate controllers following REST conventions
4. Implement background job processing with RunAnalysisJob for time-intensive calculations
5. Write request specs for API behavior and unit tests for GLCommand logic including rollback scenarios
6. Add integration tests for complete analysis workflows (submit trades -> process -> retrieve results)
7. Update Packwerk boundaries if creating new domain packs
8. Always test with sample trading data to verify financial calculations are accurate
9. Ensure proper caching of historical data to avoid repeated Alpaca API calls

### Database Changes
- Follow multi-phase deployment process: Add Col -> Write Code -> Backfill Task -> Add Constraint -> Read Code -> Drop Old Col
- Migrations must only contain schema changes
- Use separate Rake tasks for data backfills/manipulation

### Working with Packwerk
- Validate configuration: `bundle exec packwerk validate`
- Check dependencies: `bundle exec packwerk check`
- New business logic should be encapsulated in appropriate packs
- Define clear pack boundaries and dependencies

## Troubleshooting

### Environment Setup
- PostgreSQL must be running with proper database configuration
- For test environment: `RAILS_ENV=test bundle exec rails db:setup`
- Environment variables from CI reference:
  - `DATABASE_URL` format: "postgres://username:password@localhost:5432/database_name"
  - `RAILS_ENV` should be set appropriately (development, test, production)
- Check `config/database.yml` for current database configuration

### Common Issues
- **Ruby Version Mismatch**: Ensure Ruby 3.4.5 is installed and active (`ruby -v`)
- **PostgreSQL Connection**: Verify PostgreSQL is running and database exists
- **Database Name Configuration**: Note that CI may reference different database names (taskr_test vs qq_system_test) - use `config/database.yml` as authoritative source
- **Bundle Install Failures**: Check Ruby version and system dependencies are installed
- **Test Failures**: Run individual test files to isolate issues
- **Packwerk Violations**: Check `bundle exec packwerk check` output for dependency violations

### Performance Considerations
- Historical data caching is critical for analysis performance - use HistoricalBar model efficiently
- Use database indexes appropriately for time-series queries on (symbol, timestamp) combinations
- Monitor Alpaca API rate limits during data fetching operations
- Background job processing prevents API timeouts for long-running analysis calculations
- Implement intelligent gap-filling for missing historical data to minimize API calls
- Consider data retention policies for HistoricalBar cache to manage storage growth

### Network/Environment Limitations
- Some environments may block external gem/package downloads
- In restricted environments, document failures: "Ruby 3.4.5 install fails due to network restrictions - requires manual intervention"
- PostgreSQL setup may require different approaches in containerized environments

## Timing Expectations

### Build and Test Times
- **Ruby Installation**: 15-20 minutes, NEVER CANCEL, set timeout to 45+ minutes
- **Bundle Install**: 3-5 minutes, NEVER CANCEL, set timeout to 15+ minutes  
- **Database Setup**: 1-2 minutes
- **Full Test Suite**: 5-10 minutes, NEVER CANCEL, set timeout to 30+ minutes
- **Linting**: 30-60 seconds each tool
- **Asset Precompilation**: 1-2 minutes (when needed)

### Development Operations
- **Rails Server Start**: 10-30 seconds
- **Single Test File**: 10-60 seconds depending on complexity
- **Database Migration**: Usually under 30 seconds unless large data changes
- **Packwerk Validation**: 10-30 seconds

Always allow adequate time for operations to complete. Build failures due to timeouts waste more time than waiting for completion.