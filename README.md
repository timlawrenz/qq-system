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

### Running Tests

To run the full test suite:

```bash
bundle exec rspec
```

To check for Packwerk boundary violations:

```bash
bundle exec packwerk check
```
