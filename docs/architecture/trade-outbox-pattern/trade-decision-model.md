# Technical Spec: Trade Decision Model (Outbox Pattern)

**Component**: Trade Decision Outbox  
**Pack**: `packs/audit_trail/`  
**Priority**: Phase 2 (Week 1-2)

---

## Overview

Implements the **Outbox Pattern** for trade decisions:
- Capture trading **intent** before execution
- Store complete decision rationale (signals, market context, data sources)
- Link to source data via foreign keys (normalized)
- Track status lifecycle (pending → executed/failed)
- **No asynchronous execution** - preserves signal strength ordering

---

## Database Schema

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
      t.string :side, null: false  # 'buy' or 'sell'
      t.integer :quantity, null: false
      t.string :order_type, default: 'market'
      t.decimal :limit_price, precision: 10, scale: 2
      
      # Foreign key relationships (normalized)
      t.references :primary_quiver_trade, foreign_key: { to_table: :quiver_trades }
      t.references :primary_ingestion_run, foreign_key: { to_table: :data_ingestion_runs }
      
      # Decision rationale (JSONB for flexible context)
      t.jsonb :decision_rationale, null: false, default: {}
      # Structure:
      # {
      #   "signal_strength": 8.5,
      #   "confidence_score": 0.85,
      #   "trigger_event": "congressional_buy",
      #   "source_data": {
      #     "quiver_trade_ids": [123, 456],  # Array for consensus
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
      #   }
      # }
      
      # Status tracking (NO RETRY LOGIC)
      t.string :status, null: false, default: 'pending'
      # States: 'pending', 'executed', 'failed', 'cancelled'
      t.datetime :executed_at
      t.datetime :failed_at
      t.datetime :cancelled_at
      
      t.timestamps
      
      # Indexes
      t.index [:status, :created_at]
      t.index [:strategy_name, :created_at]
      t.index [:symbol, :created_at]
      t.index :decision_rationale, using: :gin
    end
  end
end
```

**Design Decisions:**

1. **Hybrid Normalization** (FK + JSONB):
   - `primary_quiver_trade_id`: FK for main signal source (enables queries)
   - `primary_ingestion_run_id`: FK to prove data availability at decision time
   - `decision_rationale`: JSONB for flexible, strategy-specific context

2. **No Retry Logic**:
   - No `retry_count` field
   - Execution is **synchronous** (preserves signal strength ordering)
   - Failed trades stay failed (no automatic retries)

3. **Status States**:
   - `pending`: Decision created, not yet executed
   - `executed`: Trade successfully filled
   - `failed`: Trade rejected (insufficient funds, API error, etc.)
   - `cancelled`: Manually cancelled before execution

---

## Model

```ruby
# packs/audit_trail/app/models/audit_trail/trade_decision.rb
module AuditTrail
  class TradeDecision < ApplicationRecord
    self.table_name = 'trade_decisions'
    
    # Associations
    has_many :trade_executions, 
             class_name: 'AuditTrail::TradeExecution',
             dependent: :destroy
    belongs_to :primary_quiver_trade, class_name: 'QuiverTrade', optional: true
    belongs_to :primary_ingestion_run, class_name: 'AuditTrail::DataIngestionRun', optional: true
    
    # Validations
    validates :decision_id, presence: true, uniqueness: true
    validates :strategy_name, presence: true
    validates :symbol, presence: true, format: { with: /\A[A-Z]{1,5}\z/ }
    validates :side, inclusion: { in: %w[buy sell] }
    validates :quantity, numericality: { greater_than: 0 }
    validates :order_type, inclusion: { in: %w[market limit] }
    validates :status, inclusion: { in: %w[pending executed failed cancelled] }
    validates :decision_rationale, presence: true
    
    # State machine
    include AASM
    
    aasm column: :status do
      state :pending, initial: true
      state :executed
      state :failed
      state :cancelled
      
      event :execute do
        transitions from: :pending, to: :executed
      end
      
      event :fail do
        transitions from: :pending, to: :failed
      end
      
      event :cancel do
        transitions from: :pending, to: :cancelled
      end
    end
    
    # Scopes
    scope :pending_decisions, -> { where(status: 'pending') }
    scope :executed_decisions, -> { where(status: 'executed') }
    scope :failed_decisions, -> { where(status: 'failed') }
    scope :for_symbol, ->(symbol) { where(symbol: symbol.upcase) }
    scope :for_strategy, ->(strategy) { where(strategy_name: strategy) }
    scope :recent, -> { where('created_at >= ?', 24.hours.ago).order(created_at: :desc) }
    scope :by_signal_strength, -> { order("(decision_rationale->>'signal_strength')::numeric DESC") }
    
    # Instance methods
    def signal_strength
      decision_rationale['signal_strength']&.to_f
    end
    
    def confidence_score
      decision_rationale['confidence_score']&.to_f
    end
    
    def source_quiver_trade_ids
      decision_rationale.dig('source_data', 'quiver_trade_ids') || []
    end
    
    def trigger_event
      decision_rationale['trigger_event']
    end
    
    def market_price_at_decision
      decision_rationale.dig('market_context', 'current_price')&.to_f
    end
    
    def buying_power_at_decision
      decision_rationale.dig('portfolio_context', 'buying_power')&.to_f
    end
    
    # Latest execution (for error messages)
    def latest_execution
      trade_executions.order(created_at: :desc).first
    end
    
    def failure_reason
      latest_execution&.error_message
    end
  end
end
```

---

## GLCommand: CreateTradeDecision

```ruby
# packs/audit_trail/app/commands/audit_trail/create_trade_decision.rb
module AuditTrail
  class CreateTradeDecision < GLCommand
    # @param strategy_name [String] e.g., "CongressionalTradingStrategy"
    # @param strategy_version [String] e.g., "1.0.0"
    # @param symbol [String] e.g., "AAPL"
    # @param side [String] "buy" or "sell"
    # @param quantity [Integer] number of shares
    # @param rationale [Hash] decision context (signals, market data, etc.)
    # @param primary_quiver_trade_id [Integer] optional FK to main signal
    
    def call
      decision = build_decision
      link_data_lineage(decision)
      
      decision.save!
      
      context.trade_decision = decision
      Rails.logger.info("✅ TradeDecision created: #{decision.decision_id} (#{decision.symbol} #{decision.side} #{decision.quantity})")
    end
    
    private
    
    def build_decision
      TradeDecision.new(
        decision_id: SecureRandom.uuid,
        strategy_name: context.strategy_name,
        strategy_version: context.strategy_version || '1.0.0',
        symbol: context.symbol.upcase,
        side: context.side.downcase,
        quantity: context.quantity,
        order_type: context.order_type || 'market',
        limit_price: context.limit_price,
        primary_quiver_trade_id: context.primary_quiver_trade_id,
        decision_rationale: context.rationale || {},
        status: 'pending'
      )
    end
    
    def link_data_lineage(decision)
      # Find recent ingestion runs that provided data
      recent_runs = DataIngestionRun
        .successful
        .where('completed_at >= ?', 24.hours.ago)
        .order(completed_at: :desc)
        .limit(5)
      
      # Enhance rationale with data lineage
      decision.decision_rationale['data_lineage'] = {
        ingestion_runs: recent_runs.map do |run|
          {
            run_id: run.run_id,
            task_name: run.task_name,
            data_source: run.data_source,
            completed_at: run.completed_at.iso8601,
            records_fetched: run.records_fetched
          }
        end
      }
      
      # Set primary_ingestion_run_id if not already set
      decision.primary_ingestion_run_id ||= recent_runs.first&.id
    end
  end
end
```

---

## Usage in Trading Strategies

### Before (Direct API Call)

```ruby
class CongressionalTradingStrategy
  def execute
    signals = generate_signals
    
    signals.each do |signal|
      # Direct API call - NO AUDIT TRAIL!
      AlpacaService.new.place_order(
        symbol: signal[:symbol],
        side: 'buy',
        quantity: signal[:quantity]
      )
    end
  end
end
```

### After (Outbox Pattern)

```ruby
# packs/trading_strategies/app/commands/trading_strategies/execute_congressional_strategy.rb
module TradingStrategies
  class ExecuteCongressionalStrategy < GLCommand
    def call
      signals = generate_signals
      
      # Sort by signal strength (strongest first)
      signals.sort_by { |s| -s[:strength] }.each do |signal|
        # 1. Create decision (audit trail)
        decision_cmd = AuditTrail::CreateTradeDecision.call(
          strategy_name: 'CongressionalTradingStrategy',
          strategy_version: '1.0.0',
          symbol: signal[:symbol],
          side: 'buy',
          quantity: signal[:quantity],
          primary_quiver_trade_id: signal[:quiver_trade_ids].first,
          rationale: {
            signal_strength: signal[:strength],
            confidence_score: signal[:confidence],
            trigger_event: 'congressional_buy',
            source_data: {
              quiver_trade_ids: signal[:quiver_trade_ids],
              politician_names: signal[:politicians],
              consensus_detected: signal[:consensus]
            },
            market_context: {
              current_price: signal[:price],
              volume_20d_avg: signal[:volume]
            },
            portfolio_context: {
              buying_power: account_buying_power,
              portfolio_value: account_portfolio_value
            }
          }
        )
        
        # 2. Execute immediately (synchronous - preserves ordering)
        execution_cmd = AuditTrail::ExecuteTradeDecision.call(
          trade_decision: decision_cmd.trade_decision
        )
        
        if execution_cmd.success?
          Rails.logger.info("✅ #{signal[:symbol]} trade executed")
        else
          Rails.logger.warn("❌ #{signal[:symbol]} trade failed: #{execution_cmd.failure_message}")
          # Continue to next signal (no retry)
        end
      end
    end
    
    private
    
    def generate_signals
      # Existing signal generation logic
    end
  end
end
```

---

## Query Examples

### Get all pending decisions

```ruby
pending = AuditTrail::TradeDecision.pending_decisions
```

### Get executed trades for symbol

```ruby
aapl_trades = AuditTrail::TradeDecision
  .executed_decisions
  .for_symbol('AAPL')
  .includes(:trade_executions, :primary_quiver_trade)
```

### Analyze failed trades

```ruby
failed = AuditTrail::TradeDecision.failed_decisions
failure_reasons = failed.map(&:failure_reason).tally

# => { "insufficient buying power" => 45, "market closed" => 3 }
```

### Find decisions from specific QuiverTrade

```ruby
quiver_trade = QuiverTrade.find(12345)
decisions = AuditTrail::TradeDecision.where(primary_quiver_trade: quiver_trade)
```

### Strategy success rate

```ruby
TradeDecision
  .group(:strategy_name)
  .select(
    'strategy_name',
    'COUNT(*) as total_signals',
    "COUNT(*) FILTER (WHERE status = 'executed') as executed",
    "COUNT(*) FILTER (WHERE status = 'failed') as failed",
    'ROUND(100.0 * COUNT(*) FILTER (WHERE status = \'executed\') / COUNT(*), 2) as success_rate'
  )
```

---

## Testing Strategy

### Unit Tests

```ruby
# spec/packs/audit_trail/models/trade_decision_spec.rb
RSpec.describe AuditTrail::TradeDecision do
  describe 'validations' do
    it { should validate_presence_of(:decision_id) }
    it { should validate_presence_of(:symbol) }
    it { should validate_inclusion_of(:side).in_array(%w[buy sell]) }
  end
  
  describe 'state machine' do
    let(:decision) { FactoryBot.create(:trade_decision, status: 'pending') }
    
    it 'transitions from pending to executed' do
      expect(decision.may_execute?).to be true
      decision.execute!
      expect(decision.executed?).to be true
    end
    
    it 'cannot execute an already executed decision' do
      decision.execute!
      expect(decision.may_execute?).to be false
    end
  end
end
```

### Command Tests

```ruby
# spec/packs/audit_trail/commands/create_trade_decision_spec.rb
RSpec.describe AuditTrail::CreateTradeDecision do
  it 'creates a trade decision with data lineage' do
    # Setup: create recent ingestion run
    ingestion_run = FactoryBot.create(:data_ingestion_run, status: 'completed')
    
    command = described_class.call(
      strategy_name: 'TestStrategy',
      symbol: 'AAPL',
      side: 'buy',
      quantity: 100,
      rationale: { signal_strength: 8.5 }
    )
    
    expect(command.success?).to be true
    decision = command.trade_decision
    expect(decision.symbol).to eq 'AAPL'
    expect(decision.decision_rationale['data_lineage']).to be_present
    expect(decision.primary_ingestion_run).to eq ingestion_run
  end
end
```

---

## Success Metrics

- ✅ 100% of trade signals create TradeDecision before execution
- ✅ FK links to QuiverTrade and DataIngestionRun
- ✅ Can reconstruct decision rationale months later
- ✅ Strategy ordering preserved (synchronous execution)
