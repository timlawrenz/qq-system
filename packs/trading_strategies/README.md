# Pack: Trading Strategies

## Purpose

This pack is responsible for defining and implementing the actual trading algorithms. It encapsulates the logic for generating investment decisions based on market data and other signals. The primary output of this pack is a "target portfolio," which represents the desired state of the trading account.

## Core Components

### Commands

-   **`TradingStrategies::GenerateTargetPortfolio`**: This is the core command that implements the "Simple" trading strategy. Its responsibilities are:
    1.  Querying the `data_fetching` pack for recent "Purchase" transactions made by members of the US Congress (`QuiverTrade` model).
    2.  Fetching the current account equity from the `alpaca_api` pack.
    3.  Calculating an equal-weight dollar value for each unique stock ticker identified.
    4.  Returning a list of `TargetPosition` value objects that represent the ideal portfolio.

### Background Jobs

-   **`ExecuteSimpleStrategyJob`**: This is the orchestrator that runs the entire trading strategy on a schedule (e.g., daily). It coordinates between this pack and the `trades` pack to execute the strategy:
    1.  It calls `GenerateTargetPortfolio` to get the desired portfolio state.
    2.  It then passes this target portfolio to the `Trades::RebalanceToTarget` command (from the `trades` pack) to execute the necessary buy and sell orders.

## Workflow

The execution of the trading strategy is designed to be an automated, background process.

1.  **Scheduled Trigger**: The `ExecuteSimpleStrategyJob` is initiated by a scheduler (e.g., Sidekiq Cron).
2.  **Target Generation**: The job first calls `TradingStrategies::GenerateTargetPortfolio`.
3.  **Signal Processing**: The command fetches all congressional purchase trades within the last 45 days and identifies the unique stock tickers.
4.  **Portfolio Calculation**: It retrieves the total equity of the Alpaca trading account and divides it equally among the identified tickers to create a target allocation.
5.  **Rebalancing**: The job takes the resulting array of `TargetPosition` objects and passes it to the `Trades::RebalanceToTarget` command.
6.  **Execution**: The `RebalanceToTarget` command (defined in the `trades` pack) compares the target portfolio to the current account holdings and places the necessary market orders to align them.
7.  **Logging**: The job logs the outcome, whether it succeeded in placing orders or failed at any step.

## Dependencies

This pack collaborates with other packs to fulfill its responsibilities:

-   **`packs/data_fetching`**: Provides the `QuiverTrade` data, which is the primary signal for the "Simple" strategy.
-   **`packs/alpaca_api`**: Provides the `AlpacaService` used to fetch real-time account data, such as total equity.
-   **`packs/trades`**: Consumes the output of this pack. The `RebalanceToTarget` command and `TargetPosition` value object from the `trades` pack are essential for executing the generated strategy.

*Note: This pack has a circular dependency with `packs/trades`, which is a known architectural decision to allow for clear separation of strategy generation from trade execution.*
