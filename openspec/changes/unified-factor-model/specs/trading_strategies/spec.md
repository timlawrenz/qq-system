# Unified Factor Model Specifications

## ADDED Requirements

### Requirement: `TradingSignal` Data Structure
The system MUST define a standardized `TradingSignal` class to encapsulate strategy outputs.

#### Scenario: Creating a valid signal
Given a strategy "Congressional"
When it generates a signal for "AAPL" with a score of 0.8
Then the `TradingSignal` object should contain:
  - ticker: "AAPL"
  - strategy_name: "Congressional"
  - score: 0.8
  - timestamp: (current time)
  - metadata: (optional hash)

#### Scenario: Validating score range
Given a strategy attempts to create a signal
When the score is 1.5 (out of bounds)
Then the `TradingSignal` initialization should raise an ArgumentError
And the error message should state "Score must be between -1.0 and 1.0"

### Requirement: `BaseStrategy` Interface
The system MUST define a `Strategies::BaseStrategy` abstract class that enforces a common interface for all strategies.

#### Scenario: Implementing a concrete strategy
Given a new strategy class `Strategies::MyNewStrategy` inheriting from `BaseStrategy`
When it implements `generate_signals(context)`
Then it should return an Array of `TradingSignal` objects

#### Scenario: Enforcing interface compliance
Given a strategy class inheriting from `BaseStrategy`
When it does not implement `generate_signals`
Then calling `generate_signals` should raise a `NotImplementedError`

### Requirement: `SignalNettingService` Logic
The system MUST implement a service to aggregate multiple `TradingSignal` objects for the same ticker into a single `NetConviction`.

#### Scenario: Netting conflicting signals
Given the following signals for "AAPL":
  - Strategy A (Weight 0.5): Score +1.0 (Buy)
  - Strategy B (Weight 0.5): Score -1.0 (Sell)
When `SignalNettingService` processes these signals
Then the Net Score should be 0.0
And the system should NOT generate a position for "AAPL"

#### Scenario: Netting reinforcing signals
Given the following signals for "MSFT":
  - Strategy A (Weight 0.6): Score +0.5
  - Strategy B (Weight 0.4): Score +1.0
When `SignalNettingService` processes these signals
Then the Net Score calculation should be: `(0.5 * 0.6) + (1.0 * 0.4) / (0.6 + 0.4)`
And the result should be +0.7

#### Scenario: Handling missing weights
Given a signal from "UnknownStrategy"
When `SignalNettingService` looks up the weight
Then it should default to 0.0 (ignore the signal)
And log a warning "Strategy UnknownStrategy not found in configuration"

### Requirement: `VolatilitySizingService` Logic
The system MUST implement a service to calculate position sizes based on asset volatility (ATR) and account equity.

#### Scenario: Sizing for high volatility
Given an account equity of $100,000
And a target risk per trade of 1.0% ($1,000 risk)
And "TSLA" has an ATR of $10.00 (High Volatility)
When `VolatilitySizingService` calculates the position size for a Net Score of +1.0
Then the number of shares should be `Risk Amount / ATR` = $1,000 / $10.00 = 100 shares
And the notional value should be `100 * Price`

#### Scenario: Sizing for low volatility
Given an account equity of $100,000
And a target risk per trade of 1.0% ($1,000 risk)
And "KO" has an ATR of $1.00 (Low Volatility)
When `VolatilitySizingService` calculates the position size for a Net Score of +1.0
Then the number of shares should be `Risk Amount / ATR` = $1,000 / $1.00 = 1,000 shares
And the notional value should be `1000 * Price` (significantly larger than TSLA position)

#### Scenario: Scaling by Conviction Score
Given a calculated "Risk Unit" of $10,000 for "AAPL" (at Score 1.0)
When the actual Net Score is +0.5
Then the final target position value should be $5,000 (`Risk Unit * 0.5`)

#### Scenario: Handling missing ATR data
Given "UnknownTicker" has no historical data for ATR calculation
When `VolatilitySizingService` attempts to size the position
Then it should fallback to a conservative default volatility (e.g., 3% daily)
Or skip the trade and log a warning "Missing ATR data for UnknownTicker"

### Requirement: `MasterAllocator` Orchestration
The system MUST implement a `MasterAllocator` command that coordinates the entire portfolio generation process.

#### Scenario: End-to-End Portfolio Generation
Given the following enabled strategies:
  - Congressional (Weight 0.5)
  - Insider (Weight 0.5)
And a total equity of $50,000
When `MasterAllocator` is called
Then it should:
  1. Call `generate_signals` on both strategies
  2. Collect all `TradingSignal` objects
  3. Pass signals to `SignalNettingService` to get `NetConviction`s
  4. Pass convictions to `VolatilitySizingService` to get `TargetPosition`s
  5. Return the final list of `TargetPosition` objects

### Requirement: Configuration Integration
The `MasterAllocator` MUST read strategy weights and risk parameters from `config/portfolio_strategies.yml`.

#### Scenario: Dynamic Configuration
Given the configuration file has:
  - risk_target_pct: 0.02 (2%)
When `MasterAllocator` runs
Then it should pass `0.02` to the `VolatilitySizingService`

## MODIFIED Requirements

### Requirement: `GenerateBlendedPortfolio`
The existing `GenerateBlendedPortfolio` command MUST be updated to use the new `MasterAllocator`.

#### Scenario: Backward Compatibility
Given the existing `GenerateBlendedPortfolio` command
When it is called
Then it should internally delegate to `MasterAllocator`
And return the same `TargetPosition` structure as before (duck typing)
So that the execution engine (`RebalanceToTarget`) does not need to change
