---
tags:
  - MOC/project
  - "#metadata/date/v1"
project_name: Untitled
status: active
jira_epic:
jira_tickets:
slack:
aliases:
  - Untitled Project
date: "{{date:YYYY-MM-DD}}"
---
# Strategic Gap Analysis & Refactoring Roadmap

## Part 1: Initial Gap Analysis

This analysis compares your current implementation (`DAILY_TRADING.md`) against the theoretical ideal outlined in your `Strategic Framework`. The primary gap is structural: the current system operates as a **Capital Allocator** (assigning budgets to independent silos), while the strategic framework demands a **Unified Factor Model** (weighing conviction against volatility).

### 1. Merging Logic Gap: Additive vs. Netting

**Current State (Siloed Buckets):** Strategies operate independently. If multiple strategies like a stock, their allocations are either added together or capped. This ignores conflicting information (e.g., Insider Buy vs. Lobbying Decrease).

- **Current Formula:**
    
    PositionFinal​=min(Cap,s=1∑n​Allocations​)
    
    _Where Allocation is a fixed dollar amount derived from a % of equity._
    

**Target State (Conviction Netting):** Strategies output a normalized "Conviction Score" (C) between -1.0 and +1.0. These are weighted and summed to create a single net signal _before_ any capital is allocated.

- **Target Formula:**
    
    SNet​=∑(Ci​×Wi​)
    
    _Where Ci​ is the conviction score of strategy i and Wi​ is the strategic weight (e.g., Congress=0.4, Insider=0.2)._
    

### 2. Position Sizing Gap: Budgeting vs. Risk Targeting

**Current State (Dollar Fixed):** Allocation is determined by account size. A low-volatility utility stock gets the same dollar allocation as a high-volatility biotech stock if the strategy weights are equal.

- **Current Formula:**
    
    Size$​=TotalEquity×StrategyWeight%​÷CountTickers​
    

**Target State (Volatility Normalization):** Allocation is determined by risk. You target a specific risk (e.g., 1% of equity at risk) and adjust the position size based on the asset's volatility (e.g., Average True Range or ATR).

- **Target Formula:**
    
    Size$​=Volatility%​TotalEquity×Risk%​​×∣SNet​∣
    
    _This ensures that a highly volatile stock receives a smaller dollar allocation to maintain consistent portfolio risk._
    

### 3. Signal Nuance Gap: Binary vs. Relative

**Current State:**

- **Lobbying:** Binary filter (Is spending up? Yes/No).
    
- **Insider:** Simple threshold (Value > $10k).
    

**Target State:**

- **Lobbying:** Relative Z-Score. How intense is the spending relative to market cap or peers?
    
- **Insider:** Signal integrity score. A $50k purchase by a CEO is weighted differently than a $50k purchase by a Director, and differently for a small-cap vs. a mega-cap.
    

### 4. Frequency Gap: Single Loop vs. Dual Loop

**Current State:** Single daily batch execution (10:00 AM).

**Target State:**

- **Core Loop (Daily):** Handles fundamental/slow data (Congress, Lobbying, Insider).
    
- **Satellite Loop (Intraday):** Handles fast data (WallStreetBets/Momentum) which cannot wait for a daily batch.
    

---

## Part 2: Refactoring Plan

This roadmap transitions the system architecture from "allocating cash" to "allocating risk."

### Phase 1: Standardization (The Signal Layer)

**Objective:** Decouple strategy logic from position sizing. Strategies should simply report _what_ they see, not _how much_ to buy.

1. **Create `TradingSignal` Object:**
    
    - Define a standard structure that all strategies must return: `{ Ticker, StrategyName, Score (-1 to 1), Metadata }`.
        
2. **Refactor Congressional Strategy:**
    
    - Remove dollar calculation logic.
        
    - Implement scoring: High Quality Politician (+1.0), Consensus (+1.2 multiplier), Standard (+0.5).
        
3. **Refactor Insider Strategy:**
    
    - Normalize transaction size against Market Cap.
        
    - Example: Purchase > 0.05% of Market Cap = Score +1.0.
        
4. **Refactor Lobbying Strategy:**
    
    - Move from binary "Did they spend?" to intensity "Spend / MarketCap".
        
    - Convert this ratio into a normalized score.
        

### Phase 2: The Master Allocator (The Core Engine)

**Objective:** Build the central brain that resolves conflicts and calculates risk.

1. **Implement Netting Service:**
    
    - Group all incoming `TradingSignal` objects by Ticker.
        
    - Apply strategic weights (e.g., Congress 40%, Lobbying 40%, Insider 20%) to calculate SNet​.
        
2. **Implement Volatility Sizing:**
    
    - Integrate a market data service (e.g., Alpaca) to fetch ATR or standard deviation for the tickers.
        
    - Apply the **Target Formula** (from Part 1) to determine the dollar size for each net score.
        
3. **Apply Constraints:**
    
    - Apply global portfolio constraints (e.g., Max leverage 1.0, Max position size 10%) _after_ the risk calculation.
        

### Phase 3: Execution (The "Diff" Engine)

**Objective:** Ensure the system trades the _difference_ between reality and the target.

1. **Fetch Current State:** Retrieve current live positions.
    
2. **Calculate Delta:** Order=Target−Current.
    
3. **Filter Noise:** Ignore orders below a specific de minimis threshold (e.g., don't trade if the delta is < $50 to save fees/complexity).
    
4. **Execute:** Send orders to Alpaca.
    

### Phase 4: Intraday Separation (WSB Strategy)

**Objective:** Integrate high-frequency signals without disrupting the daily fundamental loop.

1. **Capital Segregation:** Hard-code the Master Allocator to use only 90% of account equity. Reserve 10% for the "Satellite" loop.
    
2. **Standalone Script:** Create a separate process for Momentum/WSB signals that runs frequently (e.g., every 15 mins).
    
3. **Independence:** This script manages its own P&L bucket and does not interface with the Master Allocator's daily rebalancing.
    

### Summary of Architecture Changes

| Component            | Current Responsibility       | New Responsibility                       |
| -------------------- | ---------------------------- | ---------------------------------------- |
| **Strategy Command** | Fetch Data → **Calculate $** | Fetch Data → **Calculate Score**         |
| **Blending Service** | **Sum** Dollar Amounts       | **Net** Scores & Apply Weights           |
| **Risk Logic**       | Fixed % of Equity            | Volatility-adjusted (ATR)                |
| **Execution**        | Daily Batch (All Strategies) | Daily Batch (Core) + Intraday (Momentum) |