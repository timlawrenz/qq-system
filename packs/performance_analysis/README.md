# Pack: Performance Analysis

## Purpose

This pack is the core analysis engine responsible for calculating and reporting on the performance of trading algorithms. It orchestrates the entire process from receiving an analysis request to computing detailed financial metrics and persisting the results.

The primary goal is to provide a robust, asynchronous system for evaluating trading strategies against historical data.

## Core Components

### Models

-   **`Analysis`**: The central model of the pack. It stores the parameters for an analysis (algorithm, start/end dates), tracks its status via a state machine, and stores the final computed results in a `jsonb` column.

### API Controller

-   **`Api::V1::AnalysesController`**: Exposes the pack's functionality via a versioned JSON API. It handles incoming requests, delegates business logic to command objects, and formats the JSON responses.

### Commands (CQRS Pattern)

The pack follows the Command pattern to separate business logic from the controller and job layers.

-   **`InitiatePerformanceAnalysis`**: The primary entry point for the API. It validates input and delegates the work to `EnqueueAnalysePerformanceJob`.
-   **`EnqueueAnalysePerformanceJob`**: Creates the initial `Analysis` record with a `pending` status and enqueues the `AnalysePerformanceJob` to perform the calculations asynchronously.
-   **`AnalysePerformance`**: The core business logic command. It fetches all necessary trade and market data and uses the `PerformanceMetricsCalculator` to generate the results. This command is executed by the background job.

### Background Job

-   **`AnalysePerformanceJob`**: An ActiveJob that executes the performance analysis in the background. It manages the state transitions of the `Analysis` model (from `running` to `completed` or `failed`) and ensures that any exceptions are caught and logged to the analysis record.

### Services

-   **`PerformanceMetricsCalculator`**: A service object that encapsulates the complex financial calculations. It takes trade and market data as input and computes a wide range of metrics, including:
    -   Total Profit & Loss (PnL)
    -   Sharpe Ratio
    -   Maximum Drawdown
    -   Volatility
    -   Win/Loss Ratio
    -   A daily portfolio value time-series.

## Workflow

The performance analysis process is designed to be asynchronous to handle potentially long-running calculations without blocking the API.

1.  **Initiation**: A client sends a `POST` request to `/api/v1/analyses` with an `algorithm_id` and an optional date range.
2.  **Enqueuing**: The controller calls the `InitiatePerformanceAnalysis` command, which creates an `Analysis` record in the database with a `status` of `pending` and enqueues the `AnalysePerformanceJob`. The API responds immediately with the new `analysis_id`.
3.  **Polling**: The client can poll the `GET /api/v1/analyses/:id` endpoint to check the status of the analysis.
4.  **Execution**: The background job picks up the task, transitions the `Analysis` status to `running`, and invokes the `AnalysePerformance` command.
5.  **Calculation**: The command fetches the required data and uses the `PerformanceMetricsCalculator` service to compute the financial metrics.
6.  **Completion**: Upon successful calculation, the job updates the `Analysis` record with the results and transitions the status to `completed`. If any errors occur, the status is set to `failed` and the error message is saved.
7.  **Retrieval**: When the client polls the endpoint again, it will receive the `completed` status along with the full set of performance results.

## API Endpoints

-   **`POST /api/v1/analyses`**: Initiates a new performance analysis.
    -   **Body**:
        ```json
        {
          "algorithm_id": 1,
          "start_date": "2024-01-01", // Optional
          "end_date": "2024-01-31"   // Optional
        }
        ```
    -   **Success Response (201 Created)**:
        ```json
        {
          "analysis_id": 123,
          "status": "pending"
        }
        ```

-   **`GET /api/v1/analyses/:id`**: Retrieves the status and results of an analysis.
    -   **Success Response (200 OK)**:
        -   If pending/running:
            ```json
            {
              "analysis_id": 123,
              "status": "running"
            }
            ```
        -   If completed:
            ```json
            {
              "analysis_id": 123,
              "status": "completed",
              "results": {
                "total_pnl": 500.0,
                "sharpe_ratio": 1.5,
                "..."
              }
            }
            ```

## Dependencies

This pack relies on several other packs to function:

-   **`packs/trades`**: To access the `Trade` model for the algorithm's trading history.
-   **`packs/data_fetching`**: To fetch historical market data (`HistoricalBar`) required for calculating portfolio values.
-   **`packs/trading_strategies`**: To access the `Algorithm` model which the analysis is performed on.
