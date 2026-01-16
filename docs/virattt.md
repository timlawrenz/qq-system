# Analysis: AI Hedge Fund (virattt) vs. QQ-System

This document provides a detailed comparison between the `qq-system` (this project) and the `virattt/ai-hedge-fund` project, focusing on strategy implementation, alpha potential, and integration feasibility.

## 1. Architectural Comparison

| Feature | QQ-System | AI Hedge Fund (virattt) |
| :--- | :--- | :--- |
| **Philosophy** | Deterministic Factor-based Model | Multi-Agent LLM Collaboration |
| **Logic Type** | Rule-based (e.g., Politicians + Quality Score) | Reasoning-based (LLM analysis of news/10-Ks) |
| **Data Focus** | Alternative Data (QuiverQuant) | Mixed (News, Financials, Macro) |
| **Execution** | Automated Rebalancing (Alpaca) | Signal generation + Backtesting |
| **Scaling** | Highly scalable, low latency | High latency (LLM API calls per ticker) |

## 2. Strategy & Agent Analysis

The `ai-hedge-fund` project utilizes specialized agents that can be categorized into **Functional Analysts** and **Investor Personas**.

### Functional Analysts
| Strategy | Description | Alpha Source | Integration Complexity |
| :--- | :--- | :--- | :--- |
| **Valuation** | Calculates intrinsic value (DCF, Multiples). | **Mispricing:** Buys stocks trading below their calculated fair value. | **High:** Requires deep financial statements (Balance Sheets, Cash Flow). |
| **Sentiment** | Analyzes news and social media headlines. | **Behavioral:** Front-runs market sentiment shifts. | **Medium:** Needs a news API feed and LLM scoring. |
| **Technicals** | Standard indicators (SMA, RSI, MACD). | **Trend/Momentum:** Capitalizes on price action patterns. | **Low:** Purely mathematical, can be implemented with existing `HistoricalBar` data. |
| **Fundamentals** | Ratios (P/E, Debt/Equity, ROE). | **Quality:** Filters for financially healthy companies. | **Medium:** Needs fundamental ratio data. |

### Investor Personas
These agents use LLM prompting to mimic specific investment philosophies:
*   **Warren Buffett / Charlie Munger:** Seeks "Moats" and quality at a fair price. Alpha comes from long-term compounding.
*   **Michael Burry:** Contrarian value, looks for structural flaws or "Deep Value." Alpha comes from mean reversion.
*   **Cathie Wood:** Focuses on disruptive innovation. Alpha comes from high-beta growth momentum.
*   **Peter Lynch:** Look for "ten-baggers" in understandable businesses.

## 3. Alpha Opportunities for QQ-System

The primary "Alpha" in `qq-system` currently comes from **Information Asymmetry** (insider/congressional knowledge). Adding `virattt`-style strategies would provide **Verification Alpha**:

1.  **Sentiment Filter:** Use an LLM to check if a "Congressional Purchase" ticker is currently plagued by negative news, potentially avoiding "trap" trades.
2.  **Valuation Anchor:** Preventing the system from following a politician into a stock that is mathematically overextended (e.g., P/E > 100).
3.  **Technical Timing:** Using RSI or SMA crossovers to time the *entry* of a congressional signal more efficiently.

## 4. Integration Plan

Rather than adopting a "swarm" architecture, the most beneficial approach is to treat these agents as **new strategy classes** within the existing `TradingStrategies` namespace.

### Mapping to BaseStrategy
Each "Agent" from the AI Hedge Fund can be implemented as a class inheriting from `TradingStrategies::Strategies::BaseStrategy`.

```ruby
# Potential Implementation of a Sentiment Strategy
module TradingStrategies
  module Strategies
    class Sentiment < BaseStrategy
      def generate_signals(context)
        # 1. Fetch news for tickers with high conviction in other strategies
        # 2. Score news via LLM
        # 3. Return TradingSignal (score -1.0 to 1.0)
      end
    end
  end
end
```

### Configuration
Update `config/portfolio_strategies.yml` to weight these new "AI" signals alongside the alternative data:

```yaml
strategies:
  congressional:
    enabled: true
    weight: 0.4
  insider:
    enabled: true
    weight: 0.3
  sentiment_ai:
    enabled: true
    weight: 0.2 # New LLM-based signal
  technical_momentum:
    enabled: true
    weight: 0.1 # New mathematical signal
```

## 5. Summary Recommendation

The `virattt/ai-hedge-fund` project offers a sophisticated way to simulate human-like reasoning. For `qq-system`, the most "beneficial" path is to:
1.  Implement a **Technical Strategy** immediately (Low complexity, high benefit for timing entries).
2.  Implement an **LLM-based Sentiment Strategy** as a second layer to "veto" or "boost" congressional signals.
3.  Keep the **MasterAllocator** as the deterministic source of truth, ensuring the system remains stable and explainable.
