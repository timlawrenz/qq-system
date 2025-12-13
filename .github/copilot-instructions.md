# QuiverQuant Trading System (qq-system)

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

QuiverQuant (qq-system) is a Ruby on Rails 8.0.2.1 API-only application designed for automated trading performance analysis. The system analyzes historical trading strategy performance by processing trades against market data from the Alpaca API.

## Working Effectively

### Bootstrap and Setup Commands
- **NEVER CANCEL any build or test commands** - All commands complete quickly (under 5 seconds)
- Set timeouts to **60+ seconds minimum** for all commands to ensure completion
- Install dependencies: `bundle install` -- takes 0.4 seconds. NEVER CANCEL.
- Configure database connections (PostgreSQL via Docker on localhost:5432):
  - Development database: `qq_system_development` 
  - Test database: `qq_system_test`
  - Queue database: `qq_system_queue`
  - Username: `postgres`, Password: `password`, Host: `localhost`
- Set up databases: `bundle exec rails db:setup` -- takes 1.8 seconds. NEVER CANCEL.
- Run migrations: `bundle exec rails db:migrate` -- takes 1.7 seconds. NEVER CANCEL.

### Environment Configuration
- **Ruby Version**: 3.4.5 (located at `/opt/hostedtoolcache/Ruby/3.4.5/x64/bin/ruby`)
- **Rails Version**: 8.0.2.1
- **Database**: PostgreSQL 16 (runs via Docker container)
- **Job Queue**: SolidQueue with separate database
- Always set `SECRET_KEY_BASE` environment variable: `export SECRET_KEY_BASE=$(bundle exec rails secret)`
- Development credentials are auto-generated at `config/credentials/development.yml.enc`

### Testing and Quality Assurance
- Run test suite: `bundle exec rspec` -- takes 0.9 seconds. NEVER CANCEL. Set timeout to 60+ seconds.
  - **All tests pass**: 4 examples, 0 failures
  - Test files located in `spec/` directory
- Run linter: `bundle exec rubocop` -- takes 2.4 seconds. NEVER CANCEL. Set timeout to 60+ seconds.
  - **Always passes**: No offenses detected
- Run security scanner: `bundle exec brakeman --no-pager` -- takes 2.0 seconds. NEVER CANCEL. Set timeout to 60+ seconds.
  - **Always passes**: No security warnings
- Run dependency checker: `bundle exec packwerk check` -- takes 4.0 seconds. NEVER CANCEL. Set timeout to 60+ seconds.
- Validate Packwerk config: `bundle exec packwerk validate` -- takes 2.8 seconds. NEVER CANCEL. Set timeout to 60+ seconds.

### Running the Application
- Start Rails API server: `export SECRET_KEY_BASE=$(bundle exec rails secret) && bundle exec rails server`
  - **Server starts on**: http://localhost:3000
  - **Health check endpoint**: http://localhost:3000/up (returns green HTML page)
  - **Application type**: API-only (ActionController::API)
- Start job queue worker: `export SECRET_KEY_BASE=$(bundle exec rails secret) && bin/jobs`
  - **Note**: Requires SolidQueue database schema setup (see troubleshooting)
- Rails console: `export SECRET_KEY_BASE=$(bundle exec rails secret) && bundle exec rails console`

## Validation Scenarios

**CRITICAL**: Always run through complete end-to-end scenarios after making changes.

### Basic Application Health Check
1. Start the Rails server: `export SECRET_KEY_BASE=$(bundle exec rails secret) && bundle exec rails server`
2. Test health endpoint: `curl -s http://localhost:3000/up`
3. **Expected result**: Returns `<!DOCTYPE html><html><body style="background-color: green"></body></html>`
4. Test root endpoint: `curl -s http://localhost:3000/`
5. **Expected result**: Returns Rails welcome page
6. Stop server with Ctrl+C

### Full Development Workflow
1. **Install dependencies**: `bundle install`
2. **Set up databases**: `bundle exec rails db:setup`
3. **Run all quality checks**:
   - `bundle exec rspec` (tests)
   - `bundle exec rubocop` (linting)
   - `bundle exec brakeman --no-pager` (security)
   - `bundle exec packwerk check` (dependencies)
4. **Start application**: `export SECRET_KEY_BASE=$(bundle exec rails secret) && bundle exec rails server`
5. **Validate health**: `curl -s http://localhost:3000/up`
6. **Test console**: `export SECRET_KEY_BASE=$(bundle exec rails secret) && echo 'puts "Rails works: #{Rails.env}"' | bundle exec rails console`

## Architecture and Conventions

### Core Components
- **Controllers**: Focus on auth (Pundit), input validation, calling GLCommand, handling results
- **Business Logic**: Use `GLCommand` gem for complex operations (located in `lib/` or future `packs/`)
- **Testing Strategy**: 
  - NO controller specs
  - Isolated unit tests with mocks for GLCommands
  - Request specs for auth and HTTP responses
  - Limited integration tests for critical flows
- **Code Organization**: Uses Packwerk for domain boundaries (future packs in `packs/` directory)
- **UI Styling**: Modern Tailwind CSS v4 for any UI components
- **Job Processing**: SolidQueue for background jobs

### Data Sources

**Alpaca Trading API**:
- Market data (historical bars, real-time quotes)
- Trading execution (paper and live)
- Account management

**QuiverQuant API** (Trader Tier - Upgraded Dec 10, 2025):
- **Tier 1 Datasets** (Available):
  - Congressional Trading (House & Senate)
  - WallStreetBets sentiment
  - Wikipedia pageviews, Twitter followers, App ratings
- **Tier 2 Datasets** (NOW AVAILABLE):
  - 🆕 Corporate Insider Trading (SEC Form 4)
  - 🆕 Government Contracts (federal procurement)
  - 🆕 Corporate Lobbying (Lobbying Disclosure Act)
  - 🆕 CNBC Recommendations (media picks)
  - 🆕 Institutional Holdings (13F filings)
- **API Limits**: 1,000 calls/day (sufficient for multi-strategy platform)
- **Documentation**: See `docs/operations/QUIVER_TRADER_UPGRADE.md`

### Data Models
- **Algorithm**: Trading strategies
- **Trade**: Individual trade records (symbol, side, quantity, price, timestamp)
- **QuiverTrade**: Congressional and insider trades from QuiverQuant
- **PoliticianProfile**: Politician scoring and committee memberships
- **Analysis**: Performance analysis results with JSONB metrics
- **HistoricalBar**: Cached market data from Alpaca API
- **AlpacaOrder**: Trading execution records

### Database Configuration
```yaml
# config/database.yml - already configured for Docker PostgreSQL
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
```

## Common Tasks and File Locations

### Repository Structure
```
├── app/
│   ├── controllers/     # API controllers (ActionController::API)
│   ├── models/         # ActiveRecord models
│   ├── jobs/           # Background jobs
│   └── mailers/        # Action Mailer classes
├── spec/               # RSpec tests
├── config/             # Rails configuration
├── db/                 # Database files
│   ├── schema.rb       # Main database schema
│   ├── queue_schema.rb # SolidQueue schema
│   └── seeds.rb        # Database seeds
├── lib/                # Custom libraries
├── vendor/bundle/      # Gem dependencies
└── bin/                # Executable scripts
    ├── rails           # Rails CLI
    ├── rspec           # RSpec test runner
    ├── rubocop         # Code linter
    └── jobs            # SolidQueue worker
```

### Key Configuration Files
- `Gemfile` - Ruby dependencies
- `config/routes.rb` - API routes (currently only /up health check)
- `config/application.rb` - Rails application configuration
- `packwerk.yml` - Code organization rules
- `.rubocop.yml` - Code style rules
- `.rspec` - Test configuration

## Troubleshooting

### SolidQueue Setup (If Needed)
If job worker fails with "relation does not exist" errors:
1. Create queue database: `PGPASSWORD=password psql -h localhost -U postgres -c "CREATE DATABASE qq_system_queue;"`
2. Load queue schema: `export SECRET_KEY_BASE=$(bundle exec rails secret) && export DATABASE_URL="postgres://postgres:password@localhost:5432/qq_system_queue" && bundle exec rails runner "load 'db/queue_schema.rb'"`
3. Start worker: `export SECRET_KEY_BASE=$(bundle exec rails secret) && bin/jobs`

### Common Issues
- **Missing SECRET_KEY_BASE**: Always export before Rails commands
- **Database connection errors**: PostgreSQL runs via Docker on standard port 5432
- **Permission errors**: All bin/ scripts are executable
- **Test failures**: All tests should pass - investigate any failures immediately

### Performance Expectations
- **Bundle install**: ~0.4 seconds (gems cached)
- **Database setup**: ~1.8 seconds  
- **Database migrations**: ~1.7 seconds
- **Test suite**: ~0.9 seconds (4 examples)
- **RuboCop linting**: ~2.4 seconds
- **Brakeman security scan**: ~2.0 seconds
- **Packwerk checks**: ~4.0 seconds
- **Rails server startup**: ~2-3 seconds
- **Rails console startup**: ~1-2 seconds

**NEVER CANCEL any of these commands** - they complete quickly but set generous timeouts (60+ seconds) to ensure completion.

## CI/CD Pipeline

The `.github/workflows/ci.yml` runs:
1. **Security scan**: `bin/brakeman --no-pager`
2. **Linting**: `bin/rubocop -c .rubocop.yml`  
3. **Dependency validation**: `bin/packwerk validate` and `bin/packwerk check`
4. **Test suite**: `bundle exec rspec` with PostgreSQL service

Always run these locally before committing:
```bash
bundle exec brakeman --no-pager
bundle exec rubocop
bundle exec packwerk validate
bundle exec packwerk check  
bundle exec rspec
```

## Development Workflow

1. **Always run bootstrap first**: `bundle install && bundle exec rails db:setup`
2. **Make changes** to code
3. **Test changes**: Run relevant tests and linters
4. **Manual validation**: Start server and test key endpoints
5. **Full validation**: Run complete test suite before committing
6. **Never skip validation** - all commands run quickly

Remember: This is a **financial trading system** - accuracy and reliability are critical. Always validate changes thoroughly.