# 1. Analysis Engine Architecture

This document details the technical implementation of the performance analysis engine, focusing on the background jobs, service objects, and caching strategies.

## 1.1. Service Objects & Background Jobs

*   **`RunAnalysisJob (Sidekiq)`**: The main background job that orchestrates the entire analysis process.
*   **`Alpaca::DataFetcher`**: A service responsible for fetching historical bar data from Alpaca. It will be idempotent, checking the `HistoricalBar` cache first and only fetching data for the missing symbol/date ranges.
*   **`Performance::Calculator`**: The core logic engine. It takes a set of trades and a complete set of historical bars, calculates the daily portfolio value, and then computes all the performance metrics.

# 2. Key Performance Metrics (KPMs)

The `Performance::Calculator` service will be responsible for generating the following metrics, which will be stored in the `results` JSONB column of the `Analysis` model:

*   **Total Profit/Loss (P&L):** Absolute and percentage return over the period.
*   **Annualized Return:** The geometric average amount of money earned by an investment each year over a given time period.
*   **Volatility (Annualized Standard Deviation):** Measures the fluctuation of returns.
*   **Sharpe Ratio:** A key metric for calculating risk-adjusted return. (Higher is better).
*   **Max Drawdown:** The maximum observed loss from a peak to a trough of a portfolio, before a new peak is attained. This is a crucial measure of downside risk.
*   **Calmar Ratio:** Return vs. Max Drawdown.
*   **Win/Loss Ratio:** The number of winning trades divided by the number of losing trades.
*   **Average Win vs. Average Loss:** The average P&L for winning trades compared to the average P&L for losing trades.

# 3. Caching Strategy

Directly hitting the Alpaca API for every analysis is inefficient, slow, and will quickly exhaust rate limits. A local database cache is essential.

*   **Model:** The `HistoricalBar` table will store daily OHLCV (Open, High, Low, Close, Volume) data.
*   **Logic:** The `Alpaca::DataFetcher` service will be the sole interface for acquiring historical data.
    1.  It receives a request for a list of symbols and a date range.
    2.  It first queries the `HistoricalBar` table to see what data it already has.
    3.  It calculates the "gaps" of missing data.
    4.  It makes the minimum number of API calls to Alpaca to fill only these gaps.
    5.  The new data is persisted to the `HistoricalBar` table.
    6.  It returns the complete, cached dataset for the requested period.

This approach ensures that we only fetch any given piece of data from the Alpaca API once.

# 4. Next Steps

1.  **Alpaca Data Fetcher:** Build the `Alpaca::DataFetcher` service to connect to the Alpaca API, fetch historical bars, and populate the `HistoricalBar` cache.
2.  **Core Calculator:** Develop the `Performance::Calculator` service. This is the most complex part and will require careful, test-driven development to ensure the financial calculations are accurate.
3.  **Job Integration:** Tie everything together with the `RunAnalysisJob` using Sidekiq.
