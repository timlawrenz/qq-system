---
title: Automating Trading with Quiver Quantitative and Alpaca
date: 2025-09-14
tags:
  - trading
  - automated-trading
  - 2025/09/14
  - alpaca
  - quiver-quantitative
---

# Automating Trading with Quiver Quantitative and Alpaca

This document outlines a plan for building an automated trading system using Ruby on Rails. The system will leverage alternative data from Quiver Quantitative to generate trading signals and execute trades via the Alpaca trading API.

## Portfolio Management & Capital Allocation Strategies

A critical component of any automated trading system is how it manages the portfolio and allocates capital, especially given the constraints of a finite and potentially variable amount of cash in the trading account.

### Strategy 1: Proportional Portfolio Mirroring

This strategy attempts to replicate the portfolio of a select group of individuals (e.g., the top 5 performing members of Congress).

*   **Concept:** The system will periodically rebalance your portfolio to match the proportional holdings of the target group.
*   **Implementation:**
    1.  **Selection:** Identify a list of top-performing individuals to track based on historical data from Quiver.
    2.  **Target Portfolio:** On a schedule (e.g., daily), fetch the complete known holdings of everyone in the target group.
    3.  **Calculation:** Calculate the total value of their combined portfolio and the percentage that each stock represents. This becomes your "target allocation."
    4.  **Rebalancing:**
        *   Get your current portfolio's buying power from Alpaca.
        *   For each stock in the target allocation, calculate the dollar amount you should hold (e.g., if NVDA is 8% of the target and your buying power is $10,000, you should hold $800 of NVDA).
        *   Place buy/sell orders on Alpaca to bring your actual holdings in line with your target allocation.
*   **Pros:** Diversified, disciplined, and removes emotional decision-making.
*   **Cons/Challenges:** Requires frequent trading, which could incur transaction costs (though many platforms are now commission-free). It might also be slow to react to new trades since it's based on a snapshot of holdings.

### Strategy 2: Event-Driven Signal Following

This strategy is more reactive and trades on individual signals as they are reported.

*   **Concept:** When a trusted source (e.g., a high-performing politician or a CEO) makes a trade, treat it as a signal and execute a similar trade.
*   **Implementation:**
    1.  **Signal Generation:** Monitor the Quiver API for new transactions from your selected sources.
    2.  **Fixed-Size Trades:** For every "buy" signal, purchase a fixed dollar amount (e.g., $500) or a fixed percentage of your portfolio (e.g., 1%). This prevents a single large trade from an outsider from dominating your portfolio.
    3.  **Position Limits:** To manage risk, implement a rule to not allocate more than a certain percentage (e.g., 10%) of your total portfolio to any single stock, regardless of the number of buy signals.
    4.  **Exit Strategy:** Define clear rules for selling:
        *   **Mirror Sell:** Sell when the original source reports a sale.
        *   **Time-Based:** Sell after a fixed period (e.g., 90 days).
        *   **Profit/Loss Based:** Sell when a position hits a predefined profit target (e.g., +25%) or stop-loss (e.g., -10%).
*   **Pros:** Allows for quick reaction to new information and is simpler to implement than full portfolio rebalancing.
*   **Cons/Challenges:** Can lead to a less diversified portfolio. Requires a robust exit strategy, as sell signals may not always be available.

### Strategy 3: Conviction-Weighted Hybrid Model

This strategy combines the previous two approaches and attempts to weight trades based on the strength of the signal.

*   **Concept:** Not all signals are created equal. This strategy uses a scoring system to determine which signals to act on and how much capital to allocate.
*   **Implementation:**
    1.  **Signal Scoring:** Create a scoring system for each new trade signal. Factors could include:
        *   **Source Score:** The historical performance of the person making the trade.
        *   **Transaction Score:** The size of the transaction (larger is better).
        *   **Cluster Score:** A higher score if multiple insiders or politicians are trading the same stock around the same time.
    2.  **Core Portfolio (Mirroring):** Use ~70% of your capital to follow the "Proportional Portfolio Mirroring" strategy for a diversified base.
    3.  **Satellite Portfolio (Signal Following):** Use the remaining ~30% of your capital to act on high-scoring signals from the event-driven model. The size of the trade could be proportional to the signal's score.
*   **Pros:** A balanced approach that combines stability with the potential for higher returns from high-conviction trades.
*   **Cons/Challenges:** More complex to implement and requires careful tuning of the scoring system.

### Handling New Capital Inflows

Your system should be able to gracefully handle changes in buying power.

*   **Periodic Re-evaluation:** The easiest way is to have your daily or weekly rebalancing job always start by fetching the current buying power from Alpaca.
*   **Allocation:** Any new cash will be automatically incorporated into the portfolio during the next rebalancing cycle for the mirroring strategy. For the event-driven strategy, you could either increase the fixed size of your trades or simply have more "dry powder" available for the next signal.

## Executing Trades with the Alpaca API

The Alpaca API provides all the necessary tools to implement the trading and portfolio management strategies outlined above. Here’s how the different API features can be utilized:

### 1. Account Management (`/account`)

*   **Purpose:** This is the starting point for any trading logic. It provides the real-time status of your account, most importantly the `buying_power`.
*   **Application:** Before any rebalancing or new trade, your application must fetch the account information to know how much capital is available to be deployed. This directly addresses the challenge of a variably-sized account. You can also check if the account is restricted from trading (`trading_blocked`).

### 2. Asset Management (`/assets`)

*   **Purpose:** This endpoint allows you to query for tradable assets on Alpaca.
*   **Application:** Before placing an order for a stock ticker received from Quiver, you should first check if the asset is tradable on Alpaca (`tradable` = true). This is a crucial validation step to prevent failed orders. You can also check if an asset is `fractionable`, which is key for the portfolio management strategies.

### 3. Order Management (`/orders`)

*   **Purpose:** This is the core of trade execution. It allows you to submit, monitor, and cancel orders.
*   **Application:**
    *   **Placing Trades:** When your strategy generates a buy or sell signal, you will use this endpoint to submit the order.
    *   **Fractional Trading:** For the portfolio management strategies, you can submit orders with a `notional` value (e.g., `$500.75`) or a fractional `qty` (e.g., `3.654`). This is extremely useful for the "Proportional Portfolio Mirroring" and "Fixed-Size Trades" strategies, as it allows for precise capital allocation without being constrained by the share price.
    *   **Advanced Order Types:** Alpaca supports various order types that are critical for risk management and exit strategies:
        *   **Stop-Loss / Take-Profit:** You can create `bracket` orders that automatically place stop-loss and take-profit orders when a position is entered. This is a perfect fit for the "Event-Driven Signal Following" strategy.
        *   **Trailing Stop Orders:** For a more dynamic exit strategy, you can use trailing stop orders to lock in profits as a stock's price rises.

### 4. Position Management (`/positions`)

*   **Purpose:** This endpoint provides a list of all open positions in your account.
*   **Application:**
    *   **Portfolio Rebalancing:** For the "Proportional Portfolio Mirroring" strategy, you will fetch all current positions to compare them against your target allocation. The difference between the two will determine the buy/sell orders you need to place.
    *   **Performance Tracking:** The `avg_entry_price` of a position is crucial for calculating unrealized profit/loss and determining when to trigger a profit-target or stop-loss exit.

### 5. Real-Time Updates (WebSocket Streaming)

*   **Purpose:** The WebSocket provides real-time updates on your account, orders, and positions.
*   **Application:** While not strictly necessary for a daily rebalancing strategy, this is very useful for more advanced implementations. You can receive immediate notifications when an order is filled, which can then trigger the next step in your logic (e.g., placing a corresponding stop-loss order).

### 6. Auditing and Logging (`/account-activities`)

*   **Purpose:** This endpoint provides a historical log of all activities in your account, including trade fills, dividends, and cash transfers.
*   **Application:** This is essential for building a robust and auditable system. You can use this API to create a historical record of all trades, verify that orders were executed as expected, and debug any issues that may arise.

## Trading Strategies

Here are a few trading strategies that can be implemented using the data from Quiver Quantitative:

### 1. Congressional Trading

This strategy is based on the stock trades made by members of the U.S. Congress, which are required to be publicly disclosed. The core idea is to leverage the potential information advantage that politicians may have.

*   **Concept:** When a member of Congress buys a stock, it could be a bullish signal. Conversely, a sale could be a bearish signal. By tracking these trades, you can align your own trades with those of influential politicians.
*   **Implementation:**
    *   Use the `/beta/bulk/congresstrading` endpoint to get the latest trades.
    *   Filter for specific politicians or parties that have a strong track record.
    *   When a "Purchase" transaction is detected, initiate a "buy" order on Alpaca for the same stock.
    *   When a "Sale" transaction is detected, initiate a "sell" order.
    *   The trade size could be a fixed amount or weighted based on the reported size of the politician's transaction.

### 2. Insider Trading

This strategy involves tracking the trading activity of corporate insiders (executives, directors, and large shareholders). Insiders have a deep understanding of their company's health and prospects, making their trades a valuable signal.

*   **Concept:** A significant purchase by an insider can indicate confidence in the company's future, while a large sale might suggest the opposite.
*   **Implementation:**
    *   Use the Quiver Quantitative API to get the latest insider trading data.
    *   Filter for "Purchase" transactions from high-level executives (e.g., CEO, CFO).
    *   You could also filter for multiple insiders buying around the same time (cluster buying).
    *   When a strong buy signal is detected, place a "buy" order on Alpaca.
    *   Conversely, you could use significant sales as a signal to sell or even short a stock.

### 3. Government Contracts

This strategy focuses on companies that are awarded significant government contracts. These contracts can provide a stable and substantial revenue stream, often leading to a positive impact on the company's stock price.

*   **Concept:** When a publicly traded company is awarded a large government contract, it can be a strong bullish indicator.
*   **Implementation:**
    *   Use the Quiver Quantitative API to monitor the government contracts dataset.
    *   Filter for contracts awarded to publicly traded companies.
    *   Set a threshold for the contract amount (e.g., over $1 million) to focus on significant events.
    *   When a company is awarded a contract that meets your criteria, place a "buy" order on Alpaca for that company's stock.
    *   You would also need a corresponding sell strategy, perhaps based on a profit target, a trailing stop-loss, or after a certain period.

## Quiver Quantitative Research

### Can you buy shares using their product?

No, you cannot buy shares directly through Quiver Quantitative. It is a data and analytics platform, not a brokerage.

However, they provide a few ways to act on their data:

*   **Brokerage Partners:** They list "Interactive Brokers" and "Lightspeed" as brokerage partners. This suggests you would use the data from Quiver to inform your trading decisions and then execute the trades on a separate brokerage platform like those.
*   **Copy Trading:** They have a "Strategies Copytrading" feature through a partnership with a platform called Quantbase. This would allow you to automatically replicate the trades of their backtested strategies in your own brokerage account.

### Is there an API?

Yes, Quiver Quantitative has an API. The website footer explicitly mentions being "Powered by: QUIVER **API**" and links to `api.quiverquant.com`.

The API is the primary way to programmatically access their datasets for building your own trading algorithms, models, or dashboards. Access to the API and the ability to export data are premium features.

#### API Functionality

While the detailed API documentation was not accessible, the API homepage provides an overview of the available datasets. The API allows you to tap into the power of alternative data. With just a few lines of code, you can seamlessly integrate all of their datasets into your existing applications and algorithms.

The available datasets include:
*   Senate Trading
*   House Trading
*   Wikipedia Page Views
*   Government Contracts
*   Corporate Flights
*   WallStreetBets Discussion
*   Work Visas
*   Political Beta
*   Corporate Lobbying

[[trading-platforms]]

[[ruby-proof-of-concept]]
