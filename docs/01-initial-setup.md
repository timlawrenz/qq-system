# 1. Overview

This document outlines the brainstorming and architectural plan for a performance analysis engine. This engine will be a core component of the QuiverQuant automated trading project. Its primary purpose is to analyze the historical performance of a given trading strategy by processing a series of trades against historical market data.

The system will be an API-only service built with Ruby on Rails. It will fetch historical price data from the Alpaca Market Data API and implement a robust caching layer to ensure speed and efficiency.

# 2. Core Concept & Workflow

The fundamental idea is to create a service that can answer the question: "How well did my algorithm perform over a specific period?"

The workflow will be as follows:

1.  **Submit Trades:** An algorithm (or a user) submits a list of trades (symbol, side, quantity, timestamp) to a dedicated API endpoint.
2.  **Initiate Analysis:** The system creates an `Analysis` record with a `pending` status and queues a background job to perform the calculations. This ensures the API responds quickly.
3.  **Fetch & Cache Data:** The background job determines the unique symbols and the overall date range required for the analysis. It then intelligently fetches any missing historical price data from Alpaca's API and stores it in a local database cache.
4.  **Calculate Performance:** The job processes the trades day-by-day against the cached historical data to generate a time series of the portfolio's value.
5.  **Generate Metrics:** From the portfolio value time series, the job calculates a comprehensive suite of performance metrics (e.g., Sharpe Ratio, Max Drawdown, Total P&L).
6.  **Store & Retrieve Results:** The calculated metrics are stored in the `Analysis` record, and its status is updated to `completed`. The user can then retrieve the results from a `GET` endpoint.

# 3. System Architecture (Ruby on Rails API)

The engine will be built as a modular component within the main Rails application.

### 3.1. Data Models

*   **`Algorithm`**: Represents a trading strategy.
    *   `name`: string
    *   `description`: text

*   **`Trade`**: Stores an individual trade executed by an algorithm. This is the primary input for the analysis.
    *   `algorithm_id`: foreign key
    *   `symbol`: string
    *   `executed_at`: datetime
    *   `side`: string (buy/sell)
    *   `quantity`: decimal
    *   `price`: decimal (average fill price)

*   **`Analysis`**: Represents a single performance analysis run for an algorithm.
    *   `algorithm_id`: foreign key
    *   `start_date`: date
    *   `end_date`: date
    *   `status`: string (pending, running, completed, failed) - **Note:** This will be managed by a state machine, per `CONVENTIONS.md`.
    *   `results`: jsonb (to store the calculated metrics)

*   **`HistoricalBar`**: The caching table for market data from Alpaca.
    *   `symbol`: string
    *   `timestamp`: datetime (start of the bar, e.g., daily)
    *   `open`: decimal
    *   `high`: decimal
    *   `low`: decimal
    *   `close`: decimal
    *   `volume`: integer
    *   *Index on `(symbol, timestamp)` for fast lookups.*

### 3.2. API Endpoints & Commands

Following our conventions, controller actions will delegate all business logic to `GLCommand` objects.

*   **`POST /api/v1/analyses`**:
    *   **Action:** Kicks off a new performance analysis.
    *   **Command:** `InitiatePerformanceAnalysis`
    *   **Request Body:** `{ "algorithm_id": 1, "trades": [...] }` or just `{ "algorithm_id": 1 }` if trades are already associated with the algorithm.
    *   **Response:** `{ "analysis_id": 123, "status": "pending" }`

*   **`GET /api/v1/analyses/:id`**:
    *   **Action:** Retrieves the status and results of an analysis.
    *   **Response (Pending):** `{ "analysis_id": 123, "status": "pending" }`
    *   **Response (Completed):** `{ "analysis_id": 123, "status": "completed", "results": { ...metrics... } }`

*   **`POST /api/v1/algorithms/:algorithm_id/trades`**:
    *   **Action:** Creates a new trade for a given algorithm.
    *   **Command:** `CreateTrade`
    *   **Request Body:** `{ "trade": { "symbol": "AAPL", "executed_at": "...", "side": "buy", "quantity": 10, "price": 150.00 } }`
    *   **Response:** `{ "trade": { ... } }`

*   **`GET /api/v1/trades/:id`**:
    *   **Action:** Retrieves a specific trade.
    *   **Response:** `{ "trade": { ... } }`

*   **`PUT/PATCH /api/v1/trades/:id`**:
    *   **Action:** Updates a trade.
    *   **Command:** `UpdateTrade`
    *   **Request Body:** `{ "trade": { "quantity": 12 } }`
    *   **Response:** `{ "trade": { ... } }`

*   **`DELETE /api/v1/trades/:id`**:
    *   **Action:** Deletes a trade.
    *   **Command:** `DeleteTrade`
    *   **Response:** `204 No Content`

# 4. Modular Design with Packwerk

To ensure modularity and maintain clear boundaries, the system will be organized into the following domain-specific packs:

*   **`packs/trading_strategies`**:
    *   **Responsibility:** Manages the `Algorithm` model and related business logic.
    *   **Dependencies:** None.

*   **`packs/trades`**:
    *   **Responsibility:** Manages the `Trade` model and the `CreateTrade`, `UpdateTrade`, and `DeleteTrade` commands.
    *   **Dependencies:** `packs/trading_strategies`.

*   **`packs/data_fetching`**:
    *   **Responsibility:** Manages the `HistoricalBar` cache model and all interactions with the external Alpaca Market Data API. Will contain commands like `FetchAndCacheHistory`.
    *   **Dependencies:** None.

*   **`packs/performance_analysis`**:
    *   **Responsibility:** The core domain. Manages the `Analysis` model, the `InitiatePerformanceAnalysis` command, and the background job that orchestrates the analysis by chaining together other commands.
    *   **Dependencies:** `packs/trades`, `packs/data_fetching`.

# 5. Next Steps

1.  **Schema Design:** Implement the four Rails models (`Algorithm`, `Trade`, `Analysis`, `HistoricalBar`) within their respective packs.
2.  **API Endpoints:** Create the `AnalysesController` and `TradesController`, ensuring actions call the appropriate `GLCommand`s.

# 6. Ticket Dependency Tree

*   **[Setup] Configure Packwerk and Create Initial Packs** ([#22](https://github.com/timlawrenz/qq-system/issues/22))
    *   Dependencies: None
*   **[Database] Create `Algorithm` Model in `trading_strategies` Pack** ([#21](https://github.com/timlawrenz/qq-system/issues/21))
    *   Dependencies: #22
*   **[Database] Create `HistoricalBar` Model in `data_fetching` Pack** ([#18](https://github.com/timlawrenz/qq-system/issues/18))
    *   Dependencies: #22
*   **[Database] Create `Trade` Model in `trades` Pack** ([#19](https://github.com/timlawrenz/qq-system/issues/19))
    *   Dependencies: #21
*   **[Database] Create `Analysis` Model in `performance_analysis` Pack** ([#23](https://github.com/timlawrenz/qq-system/issues/23))
    *   Dependencies: #21
*   **[Backend] Implement Data Fetching Service for Alpaca API** ([#25](https://github.com/timlawrenz/qq-system/issues/25))
    *   Dependencies: #18
*   **[Backend] Implement `trades` API Endpoints and Commands** ([#24](https://github.com/timlawrenz/qq-system/issues/24))
    *   Dependencies: #19
*   **[Backend] Implement `InitiatePerformanceAnalysis` Command and Job** ([#26](https://github.com/timlawrenz/qq-system/issues/26))
    *   Dependencies: #19, #23, #25
*   **[Backend] Implement `analyses` API Endpoints** ([#20](https://github.com/timlawrenz/qq-system/issues/20))
    *   Dependencies: #26
*   **[Testing] Write Integration Spec for Performance Analysis Flow** ([#27](https://github.com/timlawrenz/qq-system/issues/27))
    *   Dependencies: #20