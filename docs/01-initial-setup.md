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
    *   `status`: string (pending, running, completed, failed)
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

### 3.2. API Endpoints

*   **`POST /api/v1/analyses`**:
    *   **Action:** Kicks off a new performance analysis.
    *   **Request Body:** `{ "algorithm_id": 1, "trades": [...] }` or just `{ "algorithm_id": 1 }` if trades are already associated with the algorithm.
    *   **Response:** `{ "analysis_id": 123, "status": "pending" }`

*   **`GET /api/v1/analyses/:id`**:
    *   **Action:** Retrieves the status and results of an analysis.
    *   **Response (Pending):** `{ "analysis_id": 123, "status": "pending" }`
    *   **Response (Completed):** `{ "analysis_id": 123, "status": "completed", "results": { ...metrics... } }`

*   **`POST /api/v1/algorithms/:algorithm_id/trades`**:
    *   **Action:** Creates a new trade for a given algorithm.
    *   **Request Body:** `{ "trade": { "symbol": "AAPL", "executed_at": "...", "side": "buy", "quantity": 10, "price": 150.00 } }`
    *   **Response:** `{ "trade": { ... } }`

*   **`GET /api/v1/trades/:id`**:
    *   **Action:** Retrieves a specific trade.
    *   **Response:** `{ "trade": { ... } }`

*   **`PUT/PATCH /api/v1/trades/:id`**:
    *   **Action:** Updates a trade.
    *   **Request Body:** `{ "trade": { "quantity": 12 } }`
    *   **Response:** `{ "trade": { ... } }`

*   **`DELETE /api/v1/trades/:id`**:
    *   **Action:** Deletes a trade.
    *   **Response:** `204 No Content`

# 6. Next Steps

1.  **Schema Design:** Implement the four Rails models (`Algorithm`, `Trade`, `Analysis`, `HistoricalBar`) with the specified columns and indexes.
2.  **API Endpoints:** Create the `AnalysesController` and `TradesController` with the specified CRUD actions.

# Ticket Tree

*   [Database] Create `Algorithm` model and migration (https://github.com/timlawrenz/qq-system/issues/9)
*   [Database] Create `HistoricalBar` model and migration (https://github.com/timlawrenz/qq-system/issues/4)
    *   [Database] Create `Trade` model and migration (https://github.com/timlawrenz/qq-system/issues/7)
        *   [Backend] Create `TradesController` and associated GLCommands (https://github.com/timlawrenz/qq-system/issues/8)
            *   [Testing] Write request specs for `TradesController` (https://github.com/timlawrenz/qq-system/issues/10)
    *   [Database] Create `Analysis` model and migration (https://github.com/timlawrenz/qq-system/issues/5)
        *   [Backend] Create `AnalysesController` and associated GLCommands (https://github.com/timlawrenz/qq-system/issues/6)
            *   [Testing] Write request specs for `AnalysesController` (https://github.com/timlawrenz/qq-system/issues/11)