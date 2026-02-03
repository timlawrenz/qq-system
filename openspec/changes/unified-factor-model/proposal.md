---
title: "Unified Factor Model Implementation"
type: spec
status: draft
priority: high
created: 2025-12-12
estimated_effort: 2 weeks
tags:
  - architecture
  - strategy
  - risk-management
  - refactoring
---

# OpenSpec: Unified Factor Model Implementation

## Metadata
- **Author**: GitHub Copilot
- **Date**: 2025-12-12
- **Status**: Draft
- **Priority**: High (Strategic Pivot)
- **Estimated Effort**: 2 weeks

---

## Why

The current trading system operates as a **Capital Allocator**, where individual strategies (Congressional, Insider, Lobbying) function as independent silos. Each strategy calculates its own dollar-value positions based on a fixed percentage of equity.

**Current Limitations:**
1.  **No Netting**: If Strategy A wants to Buy AAPL and Strategy B wants to Sell AAPL, the system currently either conflicts or holds both positions inefficiently. It lacks a mechanism to net these signals into a single conviction.
2.  **Inconsistent Sizing**: Position sizing is based on "budget" (e.g., $5k per stock) rather than risk. A low-volatility utility stock gets the same capital as a high-volatility biotech stock, leading to inconsistent portfolio risk.
3.  **Hard to Scale**: Adding a new strategy requires writing logic that handles capital allocation, rather than just emitting a signal.

**Target State:**
A **Unified Factor Model** where strategies are pure "Signal Generators" that output a normalized conviction score (-1.0 to +1.0). A central engine then nets these signals, applies strategic weights, and calculates position sizes based on asset volatility (ATR).

---

## Goals

1.  **Decouple Signal from Sizing**: Strategies should only say "I like this stock (Score 0.8)", not "Buy $5,000 of this stock".
2.  **Implement Signal Netting**: Combine signals from multiple strategies into a single `NetConviction` per ticker.
3.  **Implement Volatility Sizing**: Use Average True Range (ATR) to size positions such that each position contributes equal risk to the portfolio.
4.  **Standardize Extensibility**: Make adding a new strategy as simple as implementing a `generate_signals` method.

---

## What Changes

### 1. The Signal Layer (`TradingSignal`)

A standardized data structure that all strategies must return.

```ruby
# app/models/trading_signal.rb
class TradingSignal
  attr_reader :ticker, :strategy_name, :score, :metadata, :timestamp

  def initialize(ticker:, strategy_name:, score:, metadata: {}, timestamp: Time.current)
    @ticker = ticker
    @strategy_name = strategy_name
    @score = validate_score(score) # Must be -1.0 to 1.0
    @metadata = metadata
    @timestamp = timestamp
  end
  
  # ... validation logic ...
end
```

### 2. The Strategy Interface

All strategies must implement a common interface.

```ruby
# packs/trading_strategies/app/strategies/base_strategy.rb
module Strategies
  class BaseStrategy
    def generate_signals(context)
      raise NotImplementedError
    end
  end
end
```

### 3. The Netting Engine (`SignalNettingService`)

Responsible for aggregating signals.

```ruby
# Logic:
# 1. Group signals by Ticker.
# 2. Fetch Strategy Weights (e.g., Congress=0.4, Insider=0.2).
# 3. Calculate Net Score: Sum(Signal * Weight) / Sum(Weights).
```

### 4. The Risk Engine (`VolatilitySizingService`)

Responsible for converting Net Score into Dollar Allocation.

```ruby
# Logic:
# 1. Fetch ATR (Average True Range) for the ticker.
# 2. Calculate Risk Unit: (TotalEquity * TargetRisk%) / ATR.
# 3. Calculate Target Position: Risk Unit * Net Score * Price.
# 4. Apply Constraints (Max Position Size, Max Leverage).
```

---

## Implementation Plan

### Phase 1: Core Infrastructure (Days 1-3)

1.  **Define `TradingSignal`**: Create the model class.
2.  **Create `SignalNettingService`**: Implement the weighted averaging logic.
3.  **Create `VolatilitySizingService`**: Implement ATR fetching (via Alpaca) and sizing logic.
4.  **Create `MasterAllocator`**: The orchestrator that calls strategies, nets signals, and sizes positions.

### Phase 2: Strategy Refactoring (Days 4-7)

Refactor existing strategies to emit `TradingSignal`s. We can keep the old logic for backward compatibility temporarily or create "Adapters".

*   **Congressional**:
    *   Old: Returns `TargetPosition` with $ value.
    *   New: Returns `TradingSignal` with Score 1.0 (Buy) or -1.0 (Sell), boosted by Committee/Consensus.
*   **Insider**:
    *   Old: Returns `TargetPosition`.
    *   New: Returns `TradingSignal` scaled by transaction size relative to Market Cap.
*   **Lobbying**:
    *   Old: Returns `TargetPosition` (Long/Short).
    *   New: Returns `TradingSignal` based on Quintile (Q1 = +1.0, Q5 = -1.0).

### Phase 3: Integration & Migration (Days 8-10)

1.  **Update `GenerateBlendedPortfolio`**:
    *   Change it to use `MasterAllocator` instead of `BlendedPortfolioBuilder`.
2.  **Configuration Update**:
    *   Update `config/portfolio_strategies.yml` to include `risk_target_pct` (e.g., 1.0% equity at risk per trade).

---

## Extensibility: How to Add a New Strategy

To add a new strategy (e.g., "WallStreetBets Momentum"):

1.  **Create the Strategy Class**:
    ```ruby
    module Strategies
      class WallStreetBetsMomentum < BaseStrategy
        def generate_signals
          # 1. Fetch WSB data
          # 2. Calculate sentiment score (-1 to 1)
          # 3. Return [TradingSignal.new(...)]
        end
      end
    end
    ```

2.  **Register the Strategy**:
    Add it to `StrategyRegistry`.

3.  **Configure Weight**:
    Add entry to `config/portfolio_strategies.yml`:
    ```yaml
    strategies:
      wsb_momentum:
        enabled: true
        weight: 0.15
    ```

The `MasterAllocator` will automatically pick it up, net it with other signals (e.g., if Congress is buying but WSB is hating, the net score drops), and size the position based on volatility.

---

## Risk & Validation

*   **Validation**: Ensure `NetScore` never exceeds bounds [-1, 1].
*   **Failsafe**: If ATR data is missing, fallback to a conservative default volatility or skip the trade.
*   **Testing**: Unit tests for `SignalNettingService` are critical to ensure math is correct.
