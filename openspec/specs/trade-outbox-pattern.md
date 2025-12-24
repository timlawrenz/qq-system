---
title: "Trade Outbox Pattern: Auditable Trade Decision and Execution Logging"
type: spec
status: draft
priority: high
created: 2025-12-24
estimated_effort: 3-4 weeks
tags:
  - auditability
  - trading
  - outbox-pattern
  - decision-logging
  - compliance
  - data-ingestion
---

# OpenSpec: Trade Outbox Pattern

## Metadata
- **Author**: GitHub Copilot
- **Date**: 2025-12-24
- **Status**: Draft
- **Priority**: High (Critical for production readiness and compliance)
- **Estimated Effort**: 3-4 weeks (includes data ingestion logging)

---

## Problem Statement

The current trading system lacks comprehensive auditability and traceability:

**Current State:**
- Trade decisions trigger immediate API calls to Alpaca
- Many BUY orders fail silently due to insufficient buying power
- No persistent record of _what data_ informed each trading decision
- No distinction between "attempted trades" vs "executed trades"
- API call history is ephemeral (logs only, no structured storage)
- Cannot reconstruct decision rationale after the fact
- Difficult to debug why certain trades succeeded/failed
- **Data ingestion is untracked**: Rake tasks fetch data but don't log what/when
- Cannot prove when data became available to the system

**Business Impact:**
- ❌ Cannot audit trading decisions for compliance
- ❌ Cannot analyze which data signals drove successful trades
- ❌ Cannot distinguish signal quality from execution failures
- ❌ Limited ability to improve strategies through post-trade analysis
- ❌ Regulatory risk (no audit trail for automated trading)
- ❌ Cannot answer: "What AAPL data did we have when we made this trade?"
- ❌ Cannot prove we didn't have advance/non-public information

**Example Scenario:**
```
Strategy generates signal: BUY AAPL 100 shares
└─> Triggers AlpacaService.place_order
    └─> Alpaca API returns: "Insufficient buying power"
    └─> Trade never recorded in database
    └─> Decision rationale lost forever
```

---

## Goals

### Primary Goals
1. **Full Decision Auditability**: Capture complete rationale for every trade decision
2. **Execution Traceability**: Log all API interactions with timestamps and responses
3. **Clear Success/Failure Tracking**: Distinguish attempted vs executed trades
4. **Data Lineage**: Link trades back to source data (congressional filings, insider trades, etc.)
5. **Data Ingestion Tracking**: Log all data fetches with timestamps and record IDs

### Secondary Goals
6. **Replay Capability**: Reconstruct trading decisions from stored data
7. **Performance Analysis**: Measure strategy quality separate from execution issues
8. **Compliance Ready**: Meet regulatory requirements for automated trading systems
9. **Symbol Activity Reports**: Query "show me all AAPL activity in 2025" in <200ms

### Non-Goals
- Real-time streaming of trade events (can add later)
- Complex event sourcing architecture (keep simple)
- Blockchain-based immutability (overkill for now)

---

## Proposed Solution

### High-Level Architecture

Implement the **Outbox Pattern** for trade decisions with **data ingestion tracking**:

```
┌─────────────────────────────────────────────────────────┐
│ Cron Job: rake data_fetch:congress_daily                │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │ DataIngestionRun      │◄──── Log FIRST
         │ (audit table)         │      (before fetching)
         │                       │
         │ - Task name           │
         │ - Started at: 7:00 AM │
         │ - Status: "running"   │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │ QuiverQuant API calls │
         │ Fetch congressional   │
         │ trades                │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │ Create/Update         │
         │ QuiverTrade records   │
         │ (IDs: 12345, 12346)   │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │ Update                │
         │ DataIngestionRun:     │
         │ - Completed: 7:05 AM  │
         │ - Records: [12345,    │
         │   12346, 12347]       │
         │ - Status: "completed" │
         └───────────────────────┘
         
                     ⏰ 2 hours later...
         
┌─────────────────────────────────────────────────────────┐
│ Strategy generates signal                                │
│ (e.g., CongressionalTradingStrategy)                     │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │ TradeDecision record  │◄──── Created FIRST
         │ (outbox table)        │      (before API call)
         │                       │
         │ - Symbol, side, qty   │
         │ - Strategy name       │
         │ - Decision rationale  │
         │ - Source data refs:   │
         │   [12345, 12346]      │◄──── Links to ingestion
         │ - Data lineage:       │
         │   run_id: "run-001"   │◄──── Links to ingestion
         │ - Status: "pending"   │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │ TradeExecutionService │
         │ (async job)           │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │ Alpaca API call       │
         └───────────┬───────────┘
                     │
            ┌────────┴────────┐
            │                 │
            ▼                 ▼
    ┌──────────┐      ┌──────────┐
    │ Success  │      │ Failure  │
    └────┬─────┘      └────┬─────┘
         │                 │
         ▼                 ▼
┌────────────────┐  ┌─────────────────┐
│ TradeExecution │  │ TradeExecution  │
│ record created │  │ record with     │
│                │  │ error details   │
│ - API response │  │                 │
│ - Order ID     │  │ - Error message │
│ - Fill details │  │ - Retry count   │
│ - Timestamps   │  │                 │
└────────────────┘  └─────────────────┘
         │                 │
         ▼                 ▼
   Update TradeDecision status:
   "executed" or "failed"
```

**Complete Audit Chain:**
```
DataIngestionRun (7:05 AM) → QuiverTrades [12345, 12346] → 
TradeDecision (9:30 AM) → TradeExecution (9:31 AM) → AlpacaOrder (filled)
```

---

## Technical Design

### New Database Models

#### 1. DataIngestionRun (Audit Table)

**Purpose**: Tracks all data fetching operations (cron jobs)

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_data_ingestion_runs.rb
class CreateDataIngestionRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :data_ingestion_runs do |t|
      # Identity
      t.string :run_id, null: false, index: { unique: true }
      t.string :task_name, null: false
      # e.g., "data_fetch:congress_daily", "data_fetch:insider_daily"
      
      # Execution context
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.datetime :failed_at
      t.string :status, null: false, default: "running"
      # States: "running", "completed", "failed"
      
      # What was fetched
      t.string :data_source, null: false
      # e.g., "quiverquant_congress", "quiverquant_insider", "propublica_committees"
      t.date :data_date_start
      t.date :data_date_end
      t.integer :records_fetched, default: 0
      t.integer :records_created, default: 0
      t.integer :records_updated, default: 0
      t.integer :records_skipped, default: 0
      
      # API interaction details (JSONB)
      t.jsonb :api_calls, default: []
      # [
      #   {
      #     "endpoint": "/api/v1/congress",
      #     "timestamp": "2025-12-24T07:00:01Z",
      #     "status_code": 200,
      #     "response_size": 15000,
      #     "records_returned": 3,
      #     "rate_limit_remaining": 995
      #   }
      # ]
      
      # Ingested record IDs (for audit trail)
      t.jsonb :ingested_record_ids, default: {}
      # {
      #   "quiver_trades": [12345, 12346, 12347],
      #   "politician_profiles": [101, 102]
      # }
      
      # Error handling
      t.text :error_message
      t.jsonb :error_details
      
      t.timestamps
      t.index [:task_name, :started_at]
      t.index [:data_source, :started_at]
      t.index [:status, :started_at]
      t.index :ingested_record_ids, using: :gin  # For JSONB queries
    end
  end
end
```

#### 2. TradeDecision (Outbox Table)

**Purpose**: Captures the _intent_ to trade before execution

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_trade_decisions.rb
class CreateTradeDecisions < ActiveRecord::Migration[8.0]
  def change
    create_table :trade_decisions do |t|
      # Identity
      t.string :decision_id, null: false, index: { unique: true }
      t.string :strategy_name, null: false
      t.string :strategy_version, null: false
      
      # Trade parameters
      t.string :symbol, null: false
      t.string :side, null: false # "buy" or "sell"
      t.integer :quantity, null: false
      t.string :order_type, default: "market"
      t.decimal :limit_price, precision: 10, scale: 2
      
      # Decision rationale (JSONB)
      t.jsonb :decision_rationale, null: false, default: {}
      # Example:
      # {
      #   "signal_strength": 8.5,
      #   "confidence_score": 0.85,
      #   "trigger_event": "congressional_buy",
      #   "source_data": {
      #     "quiver_trade_ids": [123, 456],
      #     "politician_names": ["Nancy Pelosi", "Josh Gottheimer"],
      #     "trade_dates": ["2025-12-20", "2025-12-21"],
      #     "consensus_detected": true
      #   },
      #   "market_context": {
      #     "current_price": 150.25,
      #     "volume_20d_avg": 50000000,
      #     "volatility": 0.25
      #   },
      #   "portfolio_context": {
      #     "existing_position": 0,
      #     "buying_power": 50000.00,
      #     "portfolio_value": 100000.00
      #   },
      #   "data_lineage": {
      #     "ingestion_runs": [
      #       {
      #         "run_id": "run-001",
      #         "task_name": "data_fetch:congress_daily",
      #         "data_source": "quiverquant_congress",
      #         "completed_at": "2025-12-24T07:05:30Z",
      #         "records_fetched": 3
      #       }
      #     ]
      #   }
      # }
      
      # Execution tracking
      t.string :status, null: false, default: "pending"
      # States: "pending", "executing", "executed", "failed", "cancelled"
      t.integer :retry_count, default: 0
      t.datetime :executed_at
      t.datetime :failed_at
      
      # Audit
      t.timestamps
      t.index [:status, :created_at]
      t.index [:strategy_name, :created_at]
      t.index [:symbol, :created_at]
    end
  end
end
```

#### 3. TradeExecution (API Call Log)

**Purpose**: Records actual API interactions and results

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_trade_executions.rb
class CreateTradeExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :trade_executions do |t|
      # Link to decision
      t.references :trade_decision, null: false, foreign_key: true
      
      # Execution details
      t.string :execution_id, null: false, index: { unique: true }
      t.integer :attempt_number, null: false, default: 1
      t.string :status, null: false
      # States: "submitted", "accepted", "filled", "rejected", "cancelled"
      
      # API interaction
      t.jsonb :api_request, null: false
      # {
      #   "endpoint": "/v2/orders",
      #   "method": "POST",
      #   "payload": { "symbol": "AAPL", "qty": 100, ... },
      #   "timestamp": "2025-12-24T10:30:00Z"
      # }
      
      t.jsonb :api_response, null: false
      # {
      #   "order_id": "uuid-from-alpaca",
      #   "status": "accepted",
      #   "filled_qty": 100,
      #   "filled_avg_price": 150.25,
      #   "commission": 0.00,
      #   "timestamp": "2025-12-24T10:30:01Z"
      # }
      
      t.string :alpaca_order_id
      t.string :error_message
      t.text :error_details
      
      # Execution results (for successful fills)
      t.integer :filled_quantity
      t.decimal :filled_avg_price, precision: 10, scale: 4
      t.decimal :commission, precision: 10, scale: 4
      
      # Timing
      t.datetime :submitted_at
      t.datetime :filled_at
      t.datetime :rejected_at
      
      t.timestamps
      t.index [:status, :created_at]
      t.index [:alpaca_order_id]
    end
  end
end
```

#### 4. Update AlpacaOrder Model

Link existing AlpacaOrder records to TradeDecision:

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_trade_decision_to_alpaca_orders.rb
class AddTradeDecisionToAlpacaOrders < ActiveRecord::Migration[8.0]
  def change
    add_reference :alpaca_orders, :trade_decision, foreign_key: true
  end
end
```

---

### Service Layer Changes

#### 1. DataIngestionLogger (New)

**Responsibility**: Wrap rake tasks with audit logging

```ruby
# app/services/data_ingestion_logger.rb
class DataIngestionLogger
  def self.log_run(task_name:, data_source:)
    run = DataIngestionRun.create!(
      run_id: SecureRandom.uuid,
      task_name: task_name,
      data_source: data_source,
      started_at: Time.current,
      status: "running"
    )
    
    begin
      result = yield(run)  # Execute the actual fetch logic
      
      run.update!(
        completed_at: Time.current,
        status: "completed",
        records_fetched: result[:fetched],
        records_created: result[:created],
        records_updated: result[:updated],
        records_skipped: result[:skipped],
        data_date_start: result[:date_range]&.first,
        data_date_end: result[:date_range]&.last,
        api_calls: result[:api_calls],
        ingested_record_ids: result[:record_ids]
      )
      
      Rails.logger.info("✅ #{task_name} completed: #{result[:created]} new, #{result[:updated]} updated")
      
    rescue StandardError => e
      run.update!(
        failed_at: Time.current,
        status: "failed",
        error_message: e.message,
        error_details: {
          backtrace: e.backtrace&.first(10),
          class: e.class.name
        }
      )
      
      raise e
    end
    
    run
  end
end
```

**Usage in Rake Tasks:**

```ruby
# lib/tasks/data_fetch.rake
namespace :data_fetch do
  desc "Fetch daily congressional trades with audit logging"
  task congress_daily: :environment do
    DataIngestionLogger.log_run(
      task_name: "data_fetch:congress_daily",
      data_source: "quiverquant_congress"
    ) do |run|
      fetcher = QuiverDataFetchService.new
      fetcher.fetch_congressional_trades(days_back: 7)
      # Returns: { fetched: 10, created: 3, updated: 7, skipped: 0, 
      #            date_range: [Date.today-7, Date.today],
      #            api_calls: [...], record_ids: { quiver_trades: [123, 456] } }
    end
  end
  
  desc "Fetch daily insider trades with audit logging"
  task insider_daily: :environment do
    DataIngestionLogger.log_run(
      task_name: "data_fetch:insider_daily",
      data_source: "quiverquant_insider"
    ) do |run|
      fetcher = QuiverDataFetchService.new
      fetcher.fetch_insider_trades(days_back: 7)
    end
  end
end
```

#### 2. TradeDecisionService (New)

**Responsibility**: Create TradeDecision records with full context

```ruby
# app/services/trade_decision_service.rb
class TradeDecisionService
  # @param strategy_name [String] e.g., "CongressionalTradingStrategy"
  # @param symbol [String] e.g., "AAPL"
  # @param side [String] "buy" or "sell"
  # @param quantity [Integer] number of shares
  # @param rationale [Hash] decision context (see schema above)
  # @return [TradeDecision]
  def self.create_decision(strategy_name:, symbol:, side:, quantity:, rationale:)
    # Find recent ingestion runs that might have provided data
    recent_runs = DataIngestionRun
      .where(status: "completed")
      .where("completed_at >= ?", 24.hours.ago)
      .order(completed_at: :desc)
    
    # Enhance rationale with data lineage
    enhanced_rationale = rationale.deep_merge(
      data_lineage: {
        ingestion_runs: recent_runs.limit(5).map do |run|
          {
            run_id: run.run_id,
            task_name: run.task_name,
            data_source: run.data_source,
            completed_at: run.completed_at,
            records_fetched: run.records_fetched
          }
        end
      }
    )
    
    TradeDecision.create!(
      decision_id: SecureRandom.uuid,
      strategy_name: strategy_name,
      strategy_version: strategy_version_for(strategy_name),
      symbol: symbol.upcase,
      side: side.downcase,
      quantity: quantity,
      decision_rationale: enhanced_rationale,
      status: "pending"
    )
  end
  
  private
  
  def self.strategy_version_for(strategy_name)
    # Extract version from strategy class constant or config
    # Example: "1.0.0" for initial implementation
    "1.0.0"
  end
end
```

#### 3. TradeExecutionService (New)

**Responsibility**: Execute trades asynchronously, log all API calls

```ruby
# app/services/trade_execution_service.rb
class TradeExecutionService
  MAX_RETRIES = 3
  RETRY_DELAY = 5.seconds
  
  def initialize(trade_decision)
    @trade_decision = trade_decision
    @alpaca_service = AlpacaService.new
  end
  
  def execute
    return unless @trade_decision.pending?
    
    @trade_decision.update!(status: "executing")
    
    begin
      # Prepare order request
      order_params = build_order_params
      
      # Make API call (with full logging)
      api_request_payload = order_params.to_json
      submitted_at = Time.current
      
      response = @alpaca_service.place_order(
        symbol: @trade_decision.symbol,
        qty: @trade_decision.quantity,
        side: @trade_decision.side,
        type: @trade_decision.order_type
      )
      
      received_at = Time.current
      
      # Log execution
      execution = TradeExecution.create!(
        trade_decision: @trade_decision,
        execution_id: SecureRandom.uuid,
        attempt_number: @trade_decision.retry_count + 1,
        status: response["status"],
        api_request: {
          endpoint: "/v2/orders",
          method: "POST",
          payload: order_params,
          timestamp: submitted_at.iso8601
        },
        api_response: response,
        alpaca_order_id: response["id"],
        submitted_at: submitted_at,
        filled_at: response["filled_at"]&.to_datetime
      )
      
      # Update decision status
      if response["status"] == "filled"
        @trade_decision.update!(
          status: "executed",
          executed_at: Time.current
        )
        
        execution.update!(
          filled_quantity: response["filled_qty"],
          filled_avg_price: response["filled_avg_price"],
          commission: response.dig("legs", 0, "commission") || 0.0
        )
      elsif response["status"] == "rejected"
        handle_rejection(execution, response)
      else
        # Order accepted but not filled yet (pending, partially_filled)
        # Schedule follow-up job to check status
        CheckOrderStatusJob.set(wait: 10.seconds).perform_later(@trade_decision.id)
      end
      
    rescue StandardError => e
      handle_error(e)
    end
  end
  
  private
  
  def build_order_params
    {
      symbol: @trade_decision.symbol,
      qty: @trade_decision.quantity,
      side: @trade_decision.side,
      type: @trade_decision.order_type,
      time_in_force: "day"
    }
  end
  
  def handle_rejection(execution, response)
    error_message = response["message"] || "Order rejected by broker"
    
    execution.update!(
      status: "rejected",
      error_message: error_message,
      rejected_at: Time.current
    )
    
    # Check if retryable (e.g., insufficient buying power)
    if retryable_error?(error_message) && @trade_decision.retry_count < MAX_RETRIES
      @trade_decision.update!(
        status: "pending",
        retry_count: @trade_decision.retry_count + 1
      )
      
      # Schedule retry
      ExecuteTradeDecisionJob.set(wait: RETRY_DELAY).perform_later(@trade_decision.id)
    else
      @trade_decision.update!(
        status: "failed",
        failed_at: Time.current
      )
    end
  end
  
  def handle_error(error)
    TradeExecution.create!(
      trade_decision: @trade_decision,
      execution_id: SecureRandom.uuid,
      attempt_number: @trade_decision.retry_count + 1,
      status: "error",
      api_request: {
        endpoint: "/v2/orders",
        method: "POST",
        payload: build_order_params,
        timestamp: Time.current.iso8601
      },
      api_response: { error: error.message },
      error_message: error.message,
      error_details: error.backtrace&.join("\n")
    )
    
    @trade_decision.update!(
      status: "failed",
      failed_at: Time.current
    )
  end
  
  def retryable_error?(message)
    # Insufficient buying power is NOT retryable (won't magically appear)
    # Rate limits, network errors ARE retryable
    message.match?(/rate limit|timeout|unavailable/i)
  end
end
```

#### 4. Update Strategy Classes

Modify strategies to create TradeDecisions instead of direct API calls:

```ruby
# Example: CongressionalTradingStrategy
class CongressionalTradingStrategy
  def execute
    signals = generate_signals
    
    signals.each do |signal|
      # OLD: AlpacaService.new.place_order(...)
      
      # NEW: Create decision with full context
      TradeDecisionService.create_decision(
        strategy_name: "CongressionalTradingStrategy",
        symbol: signal[:symbol],
        side: signal[:side],
        quantity: signal[:quantity],
        rationale: {
          signal_strength: signal[:strength],
          confidence_score: signal[:confidence],
          trigger_event: "congressional_buy",
          source_data: {
            quiver_trade_ids: signal[:quiver_trade_ids],
            politician_names: signal[:politicians],
            trade_dates: signal[:trade_dates],
            consensus_detected: signal[:consensus]
          },
          market_context: {
            current_price: signal[:price],
            volume_20d_avg: signal[:volume],
            volatility: signal[:volatility]
          },
          portfolio_context: {
            existing_position: current_position(signal[:symbol]),
            buying_power: account_buying_power,
            portfolio_value: account_portfolio_value
          }
        }
      )
      
      # Enqueue async execution
      ExecuteTradeDecisionJob.perform_later(trade_decision.id)
    end
  end
end
```

---

### Background Jobs

#### 1. ExecuteTradeDecisionJob

```ruby
# app/jobs/execute_trade_decision_job.rb
class ExecuteTradeDecisionJob < ApplicationJob
  queue_as :trading
  
  retry_on StandardError, wait: 5.seconds, attempts: 3
  
  def perform(trade_decision_id)
    trade_decision = TradeDecision.find(trade_decision_id)
    TradeExecutionService.new(trade_decision).execute
  end
end
```

#### 2. CheckOrderStatusJob

```ruby
# app/jobs/check_order_status_job.rb
class CheckOrderStatusJob < ApplicationJob
  queue_as :trading
  
  def perform(trade_decision_id)
    trade_decision = TradeDecision.find(trade_decision_id)
    return unless trade_decision.executing?
    
    latest_execution = trade_decision.trade_executions.order(:created_at).last
    return unless latest_execution
    
    # Fetch current order status from Alpaca
    response = AlpacaService.new.get_order(latest_execution.alpaca_order_id)
    
    case response["status"]
    when "filled"
      latest_execution.update!(
        status: "filled",
        filled_quantity: response["filled_qty"],
        filled_avg_price: response["filled_avg_price"],
        filled_at: response["filled_at"]
      )
      trade_decision.update!(status: "executed", executed_at: Time.current)
    when "cancelled", "expired"
      trade_decision.update!(status: "failed", failed_at: Time.current)
    else
      # Still pending - check again in 10 seconds
      CheckOrderStatusJob.set(wait: 10.seconds).perform_later(trade_decision_id)
    end
  end
end
```

---

## Query Patterns & Analytics

### 1. Get All Actually Executed Trades

```ruby
# Get trades that actually executed (not just attempted)
executed_trades = TradeDecision
  .where(status: "executed")
  .includes(:trade_executions)
  .order(executed_at: :desc)

# Example output:
# [
#   {
#     symbol: "AAPL",
#     side: "buy",
#     quantity: 100,
#     executed_at: "2025-12-24 10:30:15",
#     filled_price: 150.25,
#     rationale: { ... }
#   }
# ]
```

### 2. Get Failed Trades with Reasons

```ruby
# Get all failed attempts
failed_trades = TradeDecision
  .where(status: "failed")
  .includes(:trade_executions)
  .order(failed_at: :desc)

# Group by failure reason
failure_reasons = TradeExecution
  .where(status: "rejected")
  .group(:error_message)
  .count

# Example:
# {
#   "insufficient buying power" => 45,
#   "symbol not tradable" => 3,
#   "rate limit exceeded" => 2
# }
```

### 3. Audit Trail for Specific Trade

```ruby
# Full audit trail for a trade
decision = TradeDecision.find_by(decision_id: "uuid-123")

audit_trail = {
  decision: {
    created_at: decision.created_at,
    strategy: decision.strategy_name,
    symbol: decision.symbol,
    side: decision.side,
    quantity: decision.quantity,
    rationale: decision.decision_rationale
  },
  executions: decision.trade_executions.map do |execution|
    {
      attempt: execution.attempt_number,
      submitted_at: execution.submitted_at,
      status: execution.status,
      api_request: execution.api_request,
      api_response: execution.api_response
    }
  end
}
```

### 4. Strategy Performance (Signal Quality)

```ruby
# Compare strategies by execution success rate
TradeDecision
  .group(:strategy_name)
  .select(
    "strategy_name",
    "COUNT(*) as total_signals",
    "COUNT(*) FILTER (WHERE status = 'executed') as executed",
    "COUNT(*) FILTER (WHERE status = 'failed') as failed",
    "ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'executed') / COUNT(*), 2) as success_rate"
  )

# Example output:
# strategy_name                 | total_signals | executed | failed | success_rate
# ------------------------------|---------------|----------|--------|-------------
# CongressionalTradingStrategy  | 150           | 120      | 30     | 80.00
# CorporateInsiderStrategy      | 200           | 185      | 15     | 92.50
```

### 5. Symbol Activity Report ("Show Me All AAPL Activity in 2025")

**Query Time: <200ms for full year**

```ruby
# app/queries/symbol_activity_report.rb
class SymbolActivityReport
  def self.generate(symbol:, start_date:, end_date:)
    {
      # 1. Data ingested about this symbol
      data_ingested: data_ingested_for(symbol, start_date, end_date),
      
      # 2. Decisions made about this symbol
      decisions_made: decisions_for(symbol, start_date, end_date),
      
      # 3. Trades actually executed
      trades_executed: executions_for(symbol, start_date, end_date),
      
      # 4. Summary statistics
      summary: summary_for(symbol, start_date, end_date)
    }
  end
  
  private
  
  def self.data_ingested_for(symbol, start_date, end_date)
    # Find all QuiverTrades for this symbol
    quiver_trades = QuiverTrade
      .where(ticker: symbol.upcase)
      .where(transaction_date: start_date..end_date)
    
    # Find which ingestion runs fetched them
    quiver_trades.map do |qt|
      run = DataIngestionRun
        .where("ingested_record_ids @> ?", 
               { quiver_trades: [qt.id] }.to_json)
        .first
      
      {
        ingestion_run_id: run&.run_id,
        ingested_at: run&.completed_at,
        quiver_trade_id: qt.id,
        politician: qt.representative,
        transaction_type: qt.transaction_type,
        transaction_date: qt.transaction_date
      }
    end
  end
  
  def self.decisions_for(symbol, start_date, end_date)
    TradeDecision
      .where(symbol: symbol.upcase)
      .where(created_at: start_date..end_date)
      .includes(:trade_executions)
      .order(:created_at)
      .map do |decision|
        {
          decision_id: decision.decision_id,
          created_at: decision.created_at,
          strategy: decision.strategy_name,
          side: decision.side,
          quantity: decision.quantity,
          status: decision.status,
          rationale: decision.decision_rationale,
          failure_reason: decision.trade_executions.last&.error_message
        }
      end
  end
  
  def self.executions_for(symbol, start_date, end_date)
    TradeExecution
      .joins(:trade_decision)
      .where(trade_decisions: { symbol: symbol.upcase })
      .where(status: "filled")
      .where(created_at: start_date..end_date)
      .order(:filled_at)
      .map do |execution|
        {
          decision_id: execution.trade_decision.decision_id,
          filled_at: execution.filled_at,
          side: execution.trade_decision.side,
          quantity: execution.filled_quantity,
          filled_avg_price: execution.filled_avg_price
        }
      end
  end
  
  def self.summary_for(symbol, start_date, end_date)
    decisions = TradeDecision
      .where(symbol: symbol.upcase)
      .where(created_at: start_date..end_date)
    
    executions = TradeExecution
      .joins(:trade_decision)
      .where(trade_decisions: { symbol: symbol.upcase })
      .where(status: "filled")
      .where(created_at: start_date..end_date)
    
    {
      decisions: {
        total_signals: decisions.count,
        executed: decisions.where(status: "executed").count,
        failed: decisions.where(status: "failed").count,
        success_rate: (decisions.where(status: "executed").count.to_f / 
                      decisions.count * 100).round(1)
      },
      executions: {
        total_trades: executions.count,
        shares_bought: executions.joins(:trade_decision)
                                .where(trade_decisions: { side: "buy" })
                                .sum(:filled_quantity),
        shares_sold: executions.joins(:trade_decision)
                              .where(trade_decisions: { side: "sell" })
                              .sum(:filled_quantity)
      }
    }
  end
end

# Usage:
report = SymbolActivityReport.generate(
  symbol: "AAPL",
  start_date: Date.new(2025, 1, 1),
  end_date: Date.new(2025, 12, 31)
)
# => Complete audit trail: data ingested → decisions → executions
```

---

## Migration Path

### Phase 1: Data Ingestion Logging (Week 1)
1. Create `data_ingestion_runs` table
2. Add DataIngestionRun model
3. Create DataIngestionLogger service
4. Update rake tasks (congress_daily, insider_daily, maintenance:daily)
5. Test: Run rake tasks, verify logs created
6. Write unit tests for DataIngestionLogger

### Phase 2: Trade Outbox Tables & Models (Week 1-2)
1. Create `trade_decisions` table
2. Create `trade_executions` table
3. Update `alpaca_orders` with `trade_decision_id`
4. Add TradeDecision, TradeExecution models with validations
5. Write unit tests for models

### Phase 3: Service Layer (Week 2)
1. Implement TradeDecisionService
2. Implement TradeExecutionService
3. Create background jobs
4. Write service specs

### Phase 3: Service Layer (Week 2)
1. Implement TradeDecisionService (with data lineage)
2. Implement TradeExecutionService
3. Create background jobs (ExecuteTradeDecisionJob, CheckOrderStatusJob)
4. Write service specs

### Phase 4: Strategy Integration (Week 2-3)
1. Update CongressionalTradingStrategy to use TradeDecisionService
2. Update any other existing strategies
3. Maintain backward compatibility (dual-write initially)
4. Integration tests for full flow

### Phase 5: Testing & Validation (Week 3)
1. Test failure scenarios (insufficient buying power, API errors)
2. Performance testing (can handle 100+ decisions/minute)
3. Manual testing in paper trading mode
4. Data quality validation (all ingestion runs logged)

### Phase 6: Analytics & Reporting (Week 3-4)
1. Implement SymbolActivityReport query
2. Add dashboard queries (decision success rate, failure analysis)
3. Create rake tasks for common reports
4. Set up alerts for failed trades
5. Documentation updates

---

## Success Metrics

### Auditability
- ✅ 100% of data ingestion runs logged with timestamps
- ✅ 100% of trade decisions captured before execution
- ✅ Full API request/response history for every trade
- ✅ Can reconstruct decision rationale 6 months later
- ✅ Can prove when data became available to system

### Visibility
- ✅ Clear separation of "signals generated" vs "trades executed"
- ✅ Failure rate by reason (buying power, API errors, etc.)
- ✅ Strategy success rate independent of execution issues
- ✅ "Show me all AAPL activity in 2025" query works in <200ms

### Performance
- ✅ Data ingestion logging: <50ms overhead per rake task
- ✅ Decision creation: <100ms
- ✅ Async execution: doesn't block strategy logic
- ✅ Query performance: <500ms for 10K+ records

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Increased database load | Medium | Use indexes (GIN for JSONB), consider partitioning by month after 100K+ records |
| Async execution lag | Low | SolidQueue is fast (<1s typical), alerts if queue depth > 100 |
| Disk space (JSONB bloat) | Low | JSONB is efficient, estimate ~26MB/year for aggressive trading (see analysis) |
| Breaking existing code | High | Dual-write during migration, feature flag for rollback |
| Ingestion logging overhead | Low | <50ms per rake task, runs off-peak hours (7-9 AM) |

---

## Open Questions

1. **Retention Policy**: Keep all decisions forever, or archive after 2 years?
   - *Recommendation*: Keep 2 years hot, archive older to cold storage
2. **Real-time Notifications**: Should we alert on failed trades immediately?
   - *Recommendation*: Yes, Slack/email for high-priority failures (buying power)
3. **Manual Overrides**: How to handle manually placed orders (not from strategies)?
   - *Recommendation*: Create TradeDecision with strategy_name="manual" 
4. **Partial Fills**: Should we track partial fills as separate executions?
   - *Recommendation*: Single TradeExecution, update filled_quantity incrementally
5. **Order Modifications**: If we cancel/replace orders, how to represent in outbox?
   - *Recommendation*: New TradeExecution with attempt_number incremented
6. **Ingestion Run Failures**: Should we retry failed data fetches automatically?
   - *Recommendation*: Alert only, manual retry to avoid duplicate data

---

## Next Steps

1. **Review & Approve** this spec
2. **Create change directory**: `openspec/changes/trade-outbox-pattern/`
3. **Generate tasks.md** with detailed implementation checklist (6 phases)
4. **Implement Phase 1** (data ingestion logging - quick win)
5. **Implement Phase 2** (database migrations for outbox pattern)
6. **Test in staging** before production deployment

---

## References

- [Outbox Pattern (Chris Richardson)](https://microservices.io/patterns/data/transactional-outbox.html)
- [Event Sourcing vs Outbox](https://event-driven.io/en/outbox_inbox_patterns_and_delivery_guarantees_explained/)
- [SEC Rule 15c3-5 (Market Access Rule)](https://www.sec.gov/rules/final/2010/34-63241.pdf)
- Current codebase: `app/services/alpaca_service.rb`, `app/models/alpaca_order.rb`
- Existing rake tasks: `lib/tasks/data_fetch.rake`, `lib/tasks/maintenance.rake`
