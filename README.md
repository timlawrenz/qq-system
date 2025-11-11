# QuiverQuant (QQ) Performance Analysis Engine

This project is a Ruby on Rails API-only service designed to be the core performance analysis engine for the QuiverQuant automated trading project. Its primary purpose is to analyze the historical performance of a given trading strategy by processing a series of trades against historical market data.

The system fetches historical price data from the Alpaca Market Data API and implements a robust database caching layer to ensure speed and efficiency.

## Core Concept & Workflow

The fundamental goal of this service is to answer the question: **"How well did my algorithm perform over a specific period?"**

The workflow is as follows:

1.  **Submit Trades**: An algorithm (or a user) submits a list of trades (symbol, side, quantity, timestamp) to a dedicated API endpoint.
2.  **Initiate Analysis**: The system creates an `Analysis` record with a `pending` status and queues a background job to perform the calculations. This ensures the API responds quickly without blocking.
3.  **Fetch & Cache Data**: The background job determines the unique symbols and the date range required for the analysis. It intelligently fetches any missing historical price data from Alpaca's API and stores it in a local database cache (`HistoricalBar` table).
4.  **Calculate Performance**: The job processes the trades day-by-day against the cached historical data to generate a time series of the portfolio's value.
5.  **Generate Metrics**: From the portfolio value time series, the job calculates a comprehensive suite of performance metrics (e.g., Sharpe Ratio, Max Drawdown, Total P&L).
6.  **Store & Retrieve Results**: The calculated metrics are stored in the `Analysis` record, and its status is updated to `completed`. The user can then retrieve the results from a `GET` endpoint.

## System Architecture & Modular Design

The engine is built as a modular component within a Rails application, using **Packwerk** to enforce clear boundaries between different domains.

### Packs

*   **`packs/trading_strategies`**:
    *   **Responsibility**: Manages the `Algorithm` model and related business logic.
*   **`packs/trades`**:
    *   **Responsibility**: Manages the `Trade` model and its associated API endpoints and commands (`CreateTrade`, `UpdateTrade`, `DeleteTrade`).
*   **`packs/data_fetching`**:
    *   **Responsibility**: Manages the `HistoricalBar` cache model and all interactions with the external Alpaca Market Data API.
*   **`packs/performance_analysis`**:
    *   **Responsibility**: The core domain. Manages the `Analysis` model, the `InitiatePerformanceAnalysis` command, and the background job that orchestrates the analysis.

## Key Performance Metrics (KPMs)

The analysis engine calculates the following metrics:

*   Total Profit/Loss (P&L)
*   Annualized Return
*   Volatility (Annualized Standard Deviation)
*   Sharpe Ratio
*   Max Drawdown
*   Calmar Ratio
*   Win/Loss Ratio
*   Average Win vs. Average Loss

## API Endpoints

Business logic is encapsulated in `GLCommand` objects, which are called by the controllers.

*   `POST /api/v1/analyses`: Kicks off a new performance analysis.
*   `GET /api/v1/analyses/:id`: Retrieves the status and results of an analysis.
*   `POST /api/v1/algorithms/:algorithm_id/trades`: Creates a new trade for an algorithm.
*   `GET /api/v1/trades/:id`: Retrieves a specific trade.
*   `PUT/PATCH /api/v1/trades/:id`: Updates a trade.
*   `DELETE /api/v1/trades/:id`: Deletes a trade.

## Tech Stack

*   **Backend**: Ruby on Rails 7+ (API-only)
*   **Modularity**: `packs-rails` / `packwerk`
*   **Background Jobs**: `solid_queue`
*   **Testing**: `rspec-rails`
*   **External Services**: Alpaca Market Data API

## Getting Started

### Prerequisites

- Ruby (see `.ruby-version`)
- Bundler
- PostgreSQL

### Installation

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    cd qq-system
    ```

2.  **Install dependencies:**
    ```bash
    bundle install
    ```

3.  **Set up the database:**
    ```bash
    rails db:create
    rails db:migrate
    rails db:queue:migrate
    ```

4.  **Configure environment variables:**
    Create a `.env` file and add your Alpaca API keys:
    ```
    ALPACA_API_KEY_ID=...
    ALPACA_API_SECRET_KEY=...
    ```

### Running the Application

1.  **Start the Rails server:**
    ```bash
    rails server
    ```

2.  **Start the SolidQueue worker:**
    ```bash
    bin/jobs
    ```

## Daily Operations

### Trading Workflow

The system runs an **Enhanced Congressional Trading Strategy** that combines committee oversight, quality scoring, and consensus detection to generate high-conviction trading signals.

**Daily Automated Trading:**
```bash
./daily_trading.sh
```

**Workflow:**
1. Fetches latest congressional trading data from QuiverQuant API
2. Scores politicians based on historical track record
3. Analyzes purchase signals from the last 45 days
4. Generates target portfolio using Enhanced Strategy with:
   - Committee oversight filtering (only trade stocks where politician has relevant expertise)
   - Quality score threshold (min 5.0/10 based on win rate & avg return)
   - Consensus detection (boost positions with multiple politicians buying)
   - Dynamic position sizing (weighted by quality × consensus)
5. Executes rebalancing trades on Alpaca trading account
6. Verifies positions and logs results

**Safety Features:**
- Automatic fallback to Simple Strategy if Enhanced Strategy fails
- All tests pass before each deployment
- Comprehensive logging and monitoring

**Test Strategy Comparison:**
```bash
./test_enhanced_strategy.sh
```
This script compares Simple vs Enhanced strategies side-by-side without executing trades.

**Recommended schedule:** Daily at 10:00 AM ET (30 minutes after market open)

For detailed documentation, see:
- [`DAILY_TRADING.md`](DAILY_TRADING.md) - Daily trading process
- [`ENHANCED_STRATEGY_MIGRATION.md`](ENHANCED_STRATEGY_MIGRATION.md) - Enhanced strategy details
- [`docs/QUICKSTART_TESTING.md`](docs/QUICKSTART_TESTING.md) - Testing guide

### Background Jobs

The SolidQueue worker should run continuously to process background jobs:
```bash
bin/jobs start
```

To stop the worker:
```bash
bin/jobs stop
```

### Running Tests

To run the full test suite:

```bash
bundle exec rspec
## Implemented Strategies

### 1. Enhanced Congressional Trading Strategy ✅ (Current Default)

**Status**: Production (Nov 11, 2025)  
**Openspec**: `add-enhanced-congressional-strategy` (COMPLETED & ARCHIVED)

An advanced strategy that filters congressional trading signals by committee oversight, politician quality, and consensus to generate high-conviction positions.

#### Features

1. **Committee Oversight Filtering**
   - Maps stocks to industries (Tech, Finance, Healthcare, etc.)
   - Validates politician serves on committee with industry oversight
   - Example: Only trade healthcare stocks from politicians on health committees
   - Reduces "noise" trades from unrelated expertise

2. **Politician Quality Scoring**
   - Scores each politician (0-10 scale) based on:
     - Win rate (percentage of profitable trades)
     - Average return per trade
   - Minimum threshold: 5.0/10 (configurable)
   - Automatically updated weekly via `ScorePoliticiansJob`
   - Current: 399 politician profiles scored

3. **Consensus Detection**
   - Identifies when multiple politicians buy the same stock
   - Applies position multiplier: 1.3x (2 politicians) to 2.0x (3+ politicians)
   - Helps identify high-conviction opportunities
   - Lookback period: 45 days (configurable)

4. **Dynamic Position Sizing**
   - Base weight: Number of unique politicians buying
   - Quality multiplier: 0.5x - 2.0x (based on avg politician quality score)
   - Consensus multiplier: 1.0x - 2.0x (based on politician count)
   - Final allocation: `base_weight × quality_mult × consensus_mult`

#### Configuration

Located in `daily_trading.sh`:
```ruby
TradingStrategies::GenerateEnhancedCongressionalPortfolio.call(
  enable_committee_filter: true,     # Committee oversight validation
  min_quality_score: 5.0,            # Min politician quality (0-10)
  enable_consensus_boost: true,      # Boost multi-politician signals
  lookback_days: 45                  # Signal lookback period
)
```

#### Safety Features

- **Automatic Fallback**: Reverts to Simple Strategy if enhanced filters fail
- **Zero Breaking Changes**: Simple Strategy still available for comparison
- **Comprehensive Testing**: 14/14 unit tests passing, integration tests via `test_enhanced_strategy.sh`

#### Database Schema

**New Tables** (5):
- `politician_profiles` - Historical performance tracking
- `committees` - Congressional committee data (26 committees)
- `committee_memberships` - Politician-committee associations
- `industries` - Stock industry classifications (13 industries)
- `committee_industry_mappings` - Committee oversight mappings

**Seed Data**: 26 committees, 13 industries, 100+ oversight mappings

#### Expected Performance

**Current Behavior** (Nov 11, 2025):
- Portfolio: 0 positions (filters working correctly)
- Reason: Strict quality/committee filters eliminate low-quality signals
- This is **expected and healthy** - strategy waits for high-quality signals

**As Government Shutdown Ends** (Expected 1-2 weeks):
- More congressional trades will be filed
- Quality politicians' signals will emerge
- Portfolio will build to 5-10 diversified positions
- Consensus opportunities will be detected

#### Monitoring

```bash
# Daily trading with enhanced strategy
./daily_trading.sh

# Compare simple vs enhanced strategies
./test_enhanced_strategy.sh

# View comparison results
cat tmp/strategy_comparison_report.json
```

#### Documentation

- [`ENHANCED_STRATEGY_MIGRATION.md`](ENHANCED_STRATEGY_MIGRATION.md) - Complete implementation guide
- [`docs/QUICKSTART_TESTING.md`](docs/QUICKSTART_TESTING.md) - Testing instructions
- [`openspec/changes/archive/2025-11-11-add-enhanced-congressional-strategy/`](openspec/changes/archive/2025-11-11-add-enhanced-congressional-strategy/) - Archived change proposal

---

### 2. Simple Momentum Strategy (Baseline)

**Status**: Available for comparison

This is the initial proof-of-concept strategy that serves as a baseline for performance comparison.

#### Logic

On each day of the simulation, the strategy performs the following steps:

1.  **Signal Generation**: It queries for all "Purchase" transactions by congress members where the **transaction date** falls within the last 45 days. This 45-day window is significant as it aligns with the maximum time allowed for a member of congress to disclose a trade.
2.  **Portfolio Construction**: The strategy identifies the unique stock tickers from these recent purchases.
3.  **Equal Weighting**: It calculates an equal-weight target allocation for each ticker based on the total portfolio equity. For example, if 10 unique tickers are identified, each is allocated 10% of the portfolio's value.
4.  **Rebalancing**: The system then generates the necessary buy or sell orders to align the current portfolio with this new target.

It's important to note that this strategy is based on the **transaction date**, not the disclosure date. It operates on the hypothesis that stocks recently bought by insiders may have positive momentum.

#### Backtest Results

A backtest was conducted over a two-year period from late 2023 to late 2025. The key performance metrics are as follows:

*   **Total PnL**: **$2,766.65** (2.77% return on $100k initial capital)
*   **Win/Loss Ratio**: **3.1** (3.1 winning trades for every 1 losing trade)
*   **Max Drawdown**: **1.27%** (The largest portfolio decline was very small)
*   **Sharpe Ratio**: **-1.2579**

#### Interpretation

The results indicate that the "Simple Momentum Strategy" is a **low-risk, low-return** strategy.

*   **Pros**: It is consistently profitable, with a very high win rate and exceptionally low risk of significant losses (as shown by the low max drawdown and volatility).
*   **Cons**: The returns are modest. The negative Sharpe Ratio suggests that the returns, while positive, are lower than what one might expect from a risk-free investment.

This strategy serves as a solid baseline and a successful validation of the backtesting and analysis engine. Future work could focus on refining the signal generation or allocation logic to improve returns without substantially increasing risk.
