---
title: "Tech Spec: Simple Automated Trading Bot"
date: 2025-09-20
tags:
  - "#tech-spec"
  - "#trading"
  - "#alpaca"
  - "#quiver-quantitative"
---

# 1. Overview

This document outlines the technical implementation for the "Simple Automated Trading Bot" feature. It details the data models, core logic, API interactions, and testing strategy required to build an idempotent, extensible system for automated trading based on congressional trade signals.

The core design principle is the separation of concerns between the **Strategy** (determining the desired portfolio state) and the **Execution** (making the trades necessary to achieve that state). This is facilitated by a well-defined data contract.

# 2. Data Models & Migrations

Two new ActiveRecord models will be created to store signal data and our own order data.

### 2.1. `QuiverTrade`

This model stores the raw congressional trading data fetched from the Quiver Quantitative API.

*   **Location:** `packs/data_fetching/app/models/quiver_trade.rb`
*   **Migration:** A new migration will be created to add the `quiver_trades` table.
*   **Schema:**
    | Column Name | Data Type | Description |
    | :--- | :--- | :--- |
    | `id` | `bigint` | Primary Key |
    | `ticker` | `string` | The stock ticker |
    | `company` | `string` | The name of the company |
    | `trader_name` | `string` | The name of the person/entity that made the trade |
    | `trader_source` | `string` | The source of the data (e.g., "congress") |
    | `transaction_date` | `date` | The date of the trade |
    | `transaction_type` | `string` | "Purchase" or "Sale" |
    | `trade_size_usd` | `string` | The reported size of the trade |
    | `disclosed_at` | `datetime` | The date the trade was disclosed |
    | `created_at` | `datetime` | |
    | `updated_at` | `datetime` | |

### 2.2. `AlpacaOrder`

This model logs every order placed with the Alpaca API for our own account.

*   **Location:** `packs/trades/app/models/alpaca_order.rb`
*   **Migration:** A new migration will be created to add the `alpaca_orders` table.
*   **Schema:**
    | Column Name | Data Type | Description |
    | :--- | :--- | :--- |
    | `id` | `bigint` | Primary Key |
    | `alpaca_order_id` | `uuid` | The unique ID returned by Alpaca |
    | `quiver_trade_id` | `bigint` | Foreign key to `quiver_trades`. Nullable. |
    | `symbol` | `string` | The stock ticker |
    | `side` | `string` | "buy" or "sell" |
    | `status` | `string` | The status of the order from Alpaca |
    | `qty` | `decimal` | The quantity of shares |
    | `notional` | `decimal` | The notional value of the order |
    | `order_type` | `string` | "market", "limit", etc. |
    | `time_in_force` | `string` | "day", "gtc", etc. |
    | `submitted_at` | `datetime` | Timestamp when the order was submitted |
    | `filled_at` | `datetime` | Timestamp when the order was filled |
    | `filled_avg_price` | `decimal` | The average price at which the order was filled |
    | `created_at` | `datetime` | |
    | `updated_at` | `datetime` | |

# 3. Core Logic & Data Contracts

The logic is split into a "Strategy" command that decides what to own, and an "Execution" command that carries out the trades. A PORO acts as the contract between them.

### 3.1. Data Contract: `TargetPosition` PORO

A Plain Old Ruby Object will be defined to ensure a stable interface between strategies and execution logic.

*   **Location:** `packs/trading_strategies/app/models/target_position.rb`
*   **Attributes:**
    *   `symbol` (String)
    *   `asset_type` (Symbol) - e.g., `:stock`. This allows for future extension to options, etc.
    *   `target_value` (Decimal) - The target notional value for this position.
    *   `details` (Hash) - For future use (e.g., option strike prices).

### 3.2. Strategy Command

This command encapsulates the logic for generating the target portfolio based on the "Simple" strategy.

*   **Class:** `TradingStrategies::GenerateTargetPortfolio`
*   **Location:** `packs/trading_strategies/app/commands/generate_target_portfolio.rb`
*   **Responsibilities:**
    1.  Query the `quiver_trades` table for all "Purchase" transactions within the last 45 days.
    2.  Call the `AlpacaService` to get the current total account equity.
    3.  Calculate the equal-weight dollar value for each unique ticker.
*   **Output:** An array of `TargetPosition` instances.

### 3.3. Execution Command

This command is responsible for making the current portfolio match the target state defined by the strategy.

*   **Class:** `Trades::RebalanceToTarget`
*   **Location:** `packs/trades/app/commands/rebalance_to_target.rb`
*   **Input:** A `target:` keyword argument, which is an array of `TargetPosition` objects.
*   **Responsibilities:**
    1.  Call the `AlpacaService` to get all current positions.
    2.  Compare the current positions against the target portfolio to calculate deltas.
    3.  **First, execute all sell orders** for positions that are no longer in the target portfolio.
    4.  **Then, execute all buy/adjustment orders** using notional values to match the target allocation.
    5.  Log every placed order by creating an `AlpacaOrder` record.
    6.  Initially, it will only handle `asset_type: :stock` and will raise a `NotImplementedError` for any other type.

# 4. API Services

All external API interactions will be wrapped in dedicated service classes.

### 4.1. `QuiverClient`

*   **Location:** `packs/data_fetching/app/services/quiver_client.rb`
*   **Purpose:** A dedicated client for fetching data from the Quiver Quantitative API using Faraday. It will be initialized with API keys from Rails credentials.

### 4.2. `AlpacaService`

*   **Location:** `packs/trades/app/services/alpaca_service.rb`
*   **Purpose:** A service to wrap all interactions with the `alpaca-trade-api-ruby` gem.
*   **Public Methods:**
    *   `get_account_equity()`
    *   `get_current_positions()`
    *   `place_order(symbol:, side:, notional: nil, qty: nil)`

# 5. Background Job & Orchestration

A Sidekiq job will orchestrate the entire process on a recurring schedule.

*   **Job:** `ExecuteSimpleStrategyJob`
*   **Location:** `packs/trading_strategies/app/jobs/execute_simple_strategy_job.rb`
*   **Logic:**
    ```ruby
    def perform
      target_portfolio = TradingStrategies::GenerateTargetPortfolio.call
      Trades::RebalanceToTarget.call(target: target_portfolio)
    end
    ```
*   **Scheduling:** The job will be scheduled to run daily via Sidekiq-Cron in `config/recurring.yml`.

# 6. Testing Strategy

*   **Models:** Standard model specs for validations and associations.
*   **Services:** Specs for `QuiverClient` and `AlpacaService` will use VCR to record and replay real API interactions, ensuring correct request formation and response parsing.
*   **Commands:** Command specs will use mocks and stubs to test the business logic in isolation.
    *   `GenerateTargetPortfolio` will be tested to ensure it correctly calculates target allocations based on DB state and a mocked equity value.
    *   `RebalanceToTarget` will be tested against various scenarios (e.g., empty portfolio, portfolio with sells, portfolio with adjustments) to ensure it calls the `AlpacaService` with the correct order parameters and in the correct sequence (sells then buys).
*   **Integration:** A job-level spec for `ExecuteSimpleStrategyJob` will test the full orchestration, mocking the `AlpacaService` to verify the end-to-end flow from data to trade execution signals.

# 7. Implementation Plan

This section outlines the sequence of development tasks, organized by dependencies.

*   **Foundational (No Dependencies):**
    *   [#41: [Setup] Install and configure Alpaca API client gem](https://github.com/timlawrenz/qq-system/issues/41)
    *   [#40: [Database] Create QuiverTrade model and migration](https://github.com/timlawrenz/qq-system/issues/40)
    *   [#42: [Backend] Define TargetPosition PORO](https://github.com/timlawrenz/qq-system/issues/42)
    *   [#39: [Service] Implement QuiverClient for API data fetching](https://github.com/timlawrenz/qq-system/issues/39)

*   **Dependent Tasks:**
    *   [#46: [Database] Create AlpacaOrder model and migration](https://github.com/timlawrenz/qq-system/issues/46)
        *   *Depends on: [#40](https://github.com/timlawrenz/qq-system/issues/40)*
    *   [#44: [Service] Implement AlpacaService to wrap API interactions](https://github.com/timlawrenz/qq-system/issues/44)
        *   *Depends on: [#41](https://github.com/timlawrenz/qq-system/issues/41)*
    *   [#47: [Testing] Write VCR specs for QuiverClient](https://github.com/timlawrenz/qq-system/issues/47)
        *   *Depends on: [#39](https://github.com/timlawrenz/qq-system/issues/39)*
    *   [#43: [Backend] Implement GenerateTargetPortfolio command](https://github.com/timlawrenz/qq-system/issues/43)
        *   *Depends on: [#40](https://github.com/timlawrenz/qq-system/issues/40), [#42](https://github.com/timlawrenz/qq-system/issues/42), [#44](https://github.com/timlawrenz/qq-system/issues/44)*
    *   [#49: [Testing] Write VCR specs for AlpacaService](https://github.com/timlawrenz/qq-system/issues/49)
        *   *Depends on: [#44](https://github.com/timlawrenz/qq-system/issues/44)*
    *   [#45: [Backend] Implement RebalanceToTarget command](https://github.com/timlawrenz/qq-system/issues/45)
        *   *Depends on: [#46](https://github.com/timlawrenz/qq-system/issues/46), [#43](https://github.com/timlawrenz/qq-system/issues/43)*
    *   [#51: [Job] Create and schedule ExecuteSimpleStrategyJob](https://github.com/timlawrenz/qq-system/issues/51)
        *   *Depends on: [#45](https://github.com/timlawrenz/qq-system/issues/45)*
    *   [#50: [Testing] Write command specs for strategy and execution](https://github.com/timlawrenz/qq-system/issues/50)
        *   *Depends on: [#43](https://github.com/timlawrenz/qq-system/issues/43), [#45](https://github.com/timlawrenz/qq-system/issues/45)*
    *   [#48: [Testing] Write integration spec for ExecuteSimpleStrategyJob](https://github.com/timlawrenz/qq-system/issues/48)
        *   *Depends on: [#51](https://github.com/timlawrenz/qq-system/issues/51)*