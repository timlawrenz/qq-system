---
title: "PRD: Simple Automated Trading Bot"
date: 2025-09-14
tags:
  - "#prd"
  - "#trading"
  - "#automated-trading"
  - "#alpaca"
  - "#quiver-quantitative"
  - "#ruby-on-rails"
---

# 1. Overview

This document outlines the requirements for a simple, automated trading application. The application will be a Ruby on Rails API that runs locally. It will ingest congressional trading data from the Quiver Quantitative API, use a simple strategy to identify "buy" signals, and execute trades through the Alpaca API. All data and activity will be logged to a local PostgreSQL database.

# 2. Goals and Objectives

*   **Primary Goal:** Create a functional, minimum viable product (MVP) that automates a trading strategy based on alternative data.
*   **Objectives:**
    *   Successfully fetch data from the Quiver Quantitative API.
    *   Store the ingested data in a PostgreSQL database.
    *   Implement a simple, idempotent trading logic.
    *   Successfully execute trades via the Alpaca API.
    *   Log all placed orders for future analysis.

# 3. Features & Scope

## 3.1. In Scope

*   **Configuration:** The application will be configured with API keys for Quiver Quantitative and Alpaca via Rails credentials.
*   **Data Ingestion:** A recurring background job will fetch the latest congressional trading data from the Quiver Quantitative API.
*   **Idempotent Trading Logic:** A recurring background job will:
    1.  Determine the "target portfolio" based on recent "Purchase" signals from the Quiver data.
    2.  Fetch the current portfolio state from Alpaca.
    3.  Calculate the difference between the target and current portfolios.
    4.  Execute the necessary buy/sell orders to align the current portfolio with the target state.
*   **Logging:** All fetched trades and all orders placed with Alpaca will be stored in the database.

## 3.2. Out of Scope

*   **User Interface (UI):** This is an API-only application. There will be no frontend.
*   **Authentication:** The application will run locally and will not have user authentication or authorization.
*   **Complex Strategies:** This version will only implement a simple "equal-weight portfolio of recent buy signals" strategy. More advanced portfolio weighting, stop-loss/take-profit orders, and other complex strategies are out of scope.
*   **Real-time Streaming:** The system will use periodic polling (background jobs) to fetch data, not real-time WebSocket streaming.
*   **Advanced Error Handling:** Error handling will be limited to basic logging. There will be no automated alerting or recovery mechanisms.

# 4. Execution Logic: Idempotent Rebalancing

To ensure the trading process is robust and self-correcting, it will be designed to be idempotent. This means that no matter how many times the trading job is run, it will always converge the portfolio to the same target state, which is derived from the source data.

### 4.1. Defining the Target Portfolio

*   **Source Data:** "Purchase" transactions from the `quiver_trades` table.
*   **Time Window:** The target portfolio will consist of all unique stock tickers that have had a "Purchase" transaction within the last **45 days**. This is a configurable setting.
*   **Position Sizing:** All positions in the target portfolio will be **equally weighted**. For example, if there are 10 stocks in the target portfolio, each stock will be allocated 10% of the total portfolio value.

### 4.2. The Rebalancing Job

A background job will run on a schedule (e.g., once per day) to perform the following steps:

1.  **Fetch Account Equity:** Get the total portfolio equity (the market value of all assets plus cash) from the Alpaca `/account` endpoint.
2.  **Determine Target Holdings:**
    *   Query the local database for all unique tickers with a "Purchase" transaction in the last 45 days.
    *   Calculate the target dollar value for each position (e.g., `Total Equity / Number of Tickers`).
3.  **Fetch Current Holdings:** Get the list of all current positions from the Alpaca `/positions` endpoint.
4.  **Calculate Deltas:** Compare the target holdings with the current holdings to determine what trades need to be made.
    *   **Stocks to Sell:** Any stock in the current portfolio that is *not* in the target portfolio must be sold completely.
    *   **Stocks to Buy/Adjust:** For each stock in the target portfolio, calculate the difference between the target dollar value and the current market value.
5.  **Execute Trades:**
    *   **First, execute all sell orders.** This is done to free up buying power and avoid insufficient funds errors.
    *   **Then, execute all buy orders.** Use notional orders (e.g., "buy $500 of AAPL") to precisely match the target allocation.

# 5. Technical Specifications

*   **Backend:** Ruby on Rails 8+ (in API-only mode)
*   **Database:** PostgreSQL
*   **Background Jobs:** Sidekiq with Sidekiq-Cron for scheduling.
*   **API Clients:**
    *   A custom wrapper for the Quiver Quantitative API using Faraday.
    *   The official `alpaca-trade-api-ruby` gem for the Alpaca API.

# 6. Data Models

The application will require two primary database tables:

### 6.1. `quiver_trades`

This table will store the raw data fetched from the Quiver Quantitative API.

| Column Name | Data Type | Description |
| :--- | :--- | :--- |
| `id` | `bigint` | Primary Key |
| `ticker` | `string` | The stock ticker |
| `company` | `string` | The name of the company |
| `trader_name` | `string` | The name of the person/entity that made the trade |
| `trader_source` | `string` | The source of the data (e.g., "congress", "insider") |
| `transaction_date` | `date` | The date of the trade |
| `transaction_type` | `string` | "Purchase" or "Sale" |
| `trade_size_usd` | `string` | The reported size of the trade |
| `disclosed_at` | `datetime` | The date the trade was disclosed |
| `created_at` | `datetime` | |
| `updated_at` | `datetime` | |

### 5.2. `alpaca_orders`

This table will log every order placed with the Alpaca API.

| Column Name | Data Type | Description |
| :--- | :--- | :--- |
| `id` | `bigint` | Primary Key |
| `alpaca_order_id` | `uuid` | The unique ID returned by Alpaca |
| `quiver_trade_id` | `bigint` | Foreign key to the `quiver_trades` table |
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
