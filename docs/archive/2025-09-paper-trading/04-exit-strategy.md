# Tech Spec: Time-Based Exit Strategy

This document outlines the technical specification for implementing a time-based exit strategy for the "Simple Momentum Strategy" in the backtesting engine.

### 1. Feature Details

*   **Feature Name:** Time-Based Exit for Simple Momentum Strategy
*   **Problem Statement:** The current "Simple Momentum Strategy" only has logic for entering positions based on "buy" signals. It lacks a defined exit strategy, causing positions to be held indefinitely. This prevents realizing profits, cutting losses, and reallocating capital to new opportunities.
*   **Proposed High-Level Solution:** Enhance the backtesting simulation to automatically sell any position that has been held for a predetermined number of days.
*   **Primary Pack:** `packs/trading_strategies`
*   **Relevant Existing Core Models:** `Algorithm`, `Trade`, `QuiverTrade`, `HistoricalBar`
*   **Relevant Existing Packs:** `packs/trading_strategies`, `packs/trades`, `packs/data_fetching`

### 2. Key Goals & Non-Goals

*   **Key Goals:**
    *   Implement a configurable holding period for the strategy (initially hardcoded to 90 days).
    *   The daily backtest process must check the age of each position in the simulated portfolio.
    *   When a position's age exceeds the holding period, the simulation should generate a "sell" trade to close the position.
*   **Key Non-Goals:**
    *   Implementing other types of exit strategies (e.g., stop-loss, take-profit).
    *   Making the holding period dynamically configurable via a UI or database setting.

### 3. Proposed Implementation

The implementation will be primarily focused on the `backtest:simple_strategy` rake task and its `simulate_rebalancing` helper method.

*   **Data Structure Modification:**
    *   The in-memory `current_holdings` hash will be updated to store both the quantity and the initial entry date for each position.
    *   **New Structure:**
        ```ruby
        {
          "AAPL" => { quantity: 100, entry_date: Date.parse("2024-01-15") }
        }
        ```

*   **Core Logic Changes:**
    *   **Order of Operations:** The exit logic will run at the beginning of each daily simulation cycle, *before* the `GenerateTargetPortfolio` command is called. This ensures capital from sold positions is available for immediate reallocation.
    *   **Exit Logic:** On each simulation day, the system will iterate through all positions. If a position's holding duration exceeds 90 days, a "sell" trade for the entire quantity will be created, the position removed from `current_holdings`, and the cash balance updated.
    *   **Entry Date Management:** The `entry_date` will be set only when a new position is initiated. Subsequent "buy" trades for an existing position will not reset the entry date, ensuring the 90-day clock is not reset.

### 4. Edge Cases and Handling

*   **Holding Period Ends on Non-Trading Day:** The position will be sold on the next available trading day. This is acceptable as it mirrors real-world market behavior.
*   **Partial Sells During Rebalancing:** A partial sell will not affect the `entry_date` of the position. The original entry date will be maintained.
*   **Full Liquidation:** The system is expected to handle a 100% cash portfolio gracefully, allowing the `GenerateTargetPortfolio` command to execute with the full available cash balance.

### 5. Testing Strategy

A new integration test file, `spec/tasks/backtest_time_exit_spec.rb`, will be created to verify the end-to-end behavior of the time-based exit strategy. The following scenarios will be tested:

1.  **Position correctly sold after 90 days.**
2.  **Position NOT sold before 90 days.**
3.  **Position correctly sold on the next trading day when the holding period ends on a weekend.**
