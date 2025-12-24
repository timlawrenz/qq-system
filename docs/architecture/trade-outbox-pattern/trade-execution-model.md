# Technical Spec: Trade Execution Model

**Component**: Trade Execution Logging  
**Pack**: `packs/audit_trail/`  
**Priority**: Phase 3 (Week 2)

---

## Overview

Logs actual API interactions with Alpaca for trade execution:
- **Synchronous execution** (no queuing, no retries)
- Stores references to API payloads (normalized via FK)
- Extracts key fields for efficient querying
- Links to TradeDecision (outbox pattern)

---

## Database Schema

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_trade_executions.rb
class CreateTradeExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :trade_executions do |t|
      # Link to decision
      t.references :trade_decision, null: false, 
                   foreign_key: { to_table: :trade_decisions }
      
      # Execution identity
      t.string :execution_id, null: false, index: { unique: true }
      t.integer :attempt_number, null: false, default: 1
      t.string :status, null: false
      # States: "submitted", "accepted", "filled", "rejected", "cancelled"
      
      # API payload references (normalized)
      t.references :api_request_payload, foreign_key: { to_table: :api_payloads }
      t.references :api_response_payload, foreign_key: { to_table: :api_payloads }
      
      # Extracted fields for querying (from response)
      t.string :alpaca_order_id
      t.integer :http_status_code
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
      
      # Indexes
      t.index [:status, :created_at]
      t.index :alpaca_order_id
      t.index :http_status_code
    end
  end
end

# db/migrate/YYYYMMDDHHMMSS_add_trade_decision_to_alpaca_orders.rb
class AddTradeDecisionToAlpacaOrders < ActiveRecord::Migration[8.0]
  def change
    add_reference :alpaca_orders, :trade_decision, 
                  foreign_key: { to_table: :trade_decisions }
  end
end
```

**Design Decisions:**

1. **No JSONB for API payloads** - Fully normalized via FK to `api_payloads` table
2. **Extract common fields** - For efficient queries (status, price, quantity)
3. **Single attempt only** - No retry logic (preserves signal ordering)
4. **Link to AlpacaOrder** - Maintain compatibility with existing model

---

## Model

```ruby
# packs/audit_trail/app/models/audit_trail/trade_execution.rb
module AuditTrail
  class TradeExecution < ApplicationRecord
    self.table_name = 'trade_executions'
    
    # Associations
    belongs_to :trade_decision, class_name: 'AuditTrail::TradeDecision'
    belongs_to :api_request_payload, class_name: 'AuditTrail::ApiRequest',
               foreign_key: 'api_request_payload_id', optional: true
    belongs_to :api_response_payload, class_name: 'AuditTrail::ApiResponse',
               foreign_key: 'api_response_payload_id', optional: true
    
    # Validations
    validates :execution_id, presence: true, uniqueness: true
    validates :status, inclusion: { 
      in: %w[submitted accepted filled rejected cancelled partial_fill] 
    }
    validates :attempt_number, numericality: { greater_than: 0 }
    
    # Scopes
    scope :successful, -> { where(status: 'filled') }
    scope :failed, -> { where(status: 'rejected') }
    scope :pending, -> { where(status: %w[submitted accepted]) }
    scope :recent, -> { where('created_at >= ?', 24.hours.ago).order(created_at: :desc) }
    
    # Instance methods
    def success?
      status == 'filled'
    end
    
    def failure?
      status == 'rejected'
    end
    
    def pending?
      %w[submitted accepted].include?(status)
    end
    
    # Access API payloads
    def request_payload
      api_request_payload&.payload || {}
    end
    
    def response_payload
      api_response_payload&.payload || {}
    end
    
    # Convenience accessors
    def request_endpoint
      api_request_payload&.endpoint
    end
    
    def response_status_code
      api_response_payload&.status_code
    end
    
    def api_success?
      api_response_payload&.success?
    end
  end
end
```

---

## GLCommand: ExecuteTradeDecision

```ruby
# packs/audit_trail/app/commands/audit_trail/execute_trade_decision.rb
module AuditTrail
  class ExecuteTradeDecision < GLCommand
    # @param trade_decision [TradeDecision] the decision to execute
    
    def call
      validate_decision
      
      # Build and store request
      api_request = store_request
      
      # Execute trade via Alpaca
      response = execute_alpaca_order
      
      # Store response
      api_response = store_response(response)
      
      # Create execution record
      execution = create_execution(api_request, api_response, response)
      
      # Update decision status
      update_decision(execution)
      
      context.trade_execution = execution
      
      if execution.success?
        Rails.logger.info("✅ Trade executed: #{execution.execution_id}")
      else
        Rails.logger.warn("❌ Trade failed: #{execution.error_message}")
      end
    end
    
    private
    
    def validate_decision
      decision = context.trade_decision
      
      unless decision.pending?
        raise GLCommand::FailureError, "Decision #{decision.decision_id} is not pending"
      end
    end
    
    def store_request
      request_data = {
        endpoint: '/v2/orders',
        method: 'POST',
        payload: {
          symbol: context.trade_decision.symbol,
          qty: context.trade_decision.quantity,
          side: context.trade_decision.side,
          type: context.trade_decision.order_type,
          time_in_force: 'day'
        }
      }
      
      ApiRequest.create!(
        payload: request_data,
        source: 'alpaca',
        captured_at: Time.current
      )
    end
    
    def execute_alpaca_order
      alpaca_service = AlpacaApi::AlpacaService.new
      
      alpaca_service.place_order(
        symbol: context.trade_decision.symbol,
        qty: context.trade_decision.quantity,
        side: context.trade_decision.side,
        type: context.trade_decision.order_type
      )
    rescue StandardError => e
      # Return error as pseudo-response
      {
        'status' => 'error',
        'message' => e.message,
        'http_status' => 500
      }
    end
    
    def store_response(response)
      ApiResponse.create!(
        payload: response,
        source: 'alpaca',
        captured_at: Time.current
      )
    end
    
    def create_execution(api_request, api_response, response)
      TradeExecution.create!(
        trade_decision: context.trade_decision,
        execution_id: SecureRandom.uuid,
        attempt_number: 1,  # Always 1 (no retries)
        status: map_alpaca_status(response['status']),
        api_request_payload: api_request,
        api_response_payload: api_response,
        alpaca_order_id: response['id'],
        http_status_code: response['http_status'] || 200,
        error_message: response['message'],
        filled_quantity: response['filled_qty'],
        filled_avg_price: response['filled_avg_price'],
        commission: response.dig('legs', 0, 'commission') || 0.0,
        submitted_at: Time.current,
        filled_at: response['filled_at']&.to_datetime,
        rejected_at: response['status'] == 'rejected' ? Time.current : nil
      )
    end
    
    def map_alpaca_status(alpaca_status)
      case alpaca_status
      when 'new', 'pending_new' then 'submitted'
      when 'accepted', 'pending_replace' then 'accepted'
      when 'filled' then 'filled'
      when 'rejected', 'canceled' then 'rejected'
      when 'partially_filled' then 'partial_fill'
      when 'error', nil then 'rejected'
      else 'submitted'
      end
    end
    
    def update_decision(execution)
      decision = context.trade_decision
      
      if execution.success?
        decision.execute!
        decision.update!(executed_at: Time.current)
      else
        decision.fail!
        decision.update!(failed_at: Time.current)
      end
    end
  end
end
```

---

## Integration with AlpacaService

### Current AlpacaService

```ruby
# packs/alpaca_api/app/services/alpaca_service.rb
class AlpacaService
  def place_order(symbol:, qty:, side:, type: 'market')
    # Makes HTTP request to Alpaca
    # Returns response hash
  end
end
```

**No changes needed!** ExecuteTradeDecision command wraps it.

---

## Usage Pattern

### In Trading Strategy

```ruby
# After creating TradeDecision
decision_cmd = AuditTrail::CreateTradeDecision.call(...)

# Execute immediately (synchronous)
execution_cmd = AuditTrail::ExecuteTradeDecision.call(
  trade_decision: decision_cmd.trade_decision
)

if execution_cmd.success?
  puts "✅ Trade executed: #{execution_cmd.trade_execution.alpaca_order_id}"
else
  puts "❌ Trade failed: #{execution_cmd.failure_message}"
  # Continue to next signal (no retry)
end
```

---

## Query Examples

### Get all filled executions for symbol

```ruby
filled_trades = AuditTrail::TradeExecution
  .successful
  .joins(:trade_decision)
  .where(trade_decisions: { symbol: 'AAPL' })
  .includes(:api_request_payload, :api_response_payload)
```

### Failure analysis

```ruby
failures = AuditTrail::TradeExecution.failed
failure_reasons = failures.map(&:error_message).tally

# => {
#   "403 insufficient buying power" => 45,
#   "422 symbol not tradable" => 3,
#   "429 rate limit exceeded" => 2
# }
```

### Find execution by Alpaca order ID

```ruby
execution = AuditTrail::TradeExecution.find_by(alpaca_order_id: 'abc-123')
decision = execution.trade_decision

# Full context
{
  decision: {
    strategy: decision.strategy_name,
    signal_strength: decision.signal_strength,
    created_at: decision.created_at
  },
  execution: {
    filled_qty: execution.filled_quantity,
    filled_price: execution.filled_avg_price,
    api_request: execution.request_payload,
    api_response: execution.response_payload
  }
}
```

---

## Error Handling

### Insufficient Buying Power

```ruby
# Alpaca response:
# { "code": 40310000, "message": "insufficient buying power" }

# Stored as:
execution.status = 'rejected'
execution.error_message = 'insufficient buying power'
execution.http_status_code = 403

# Decision marked as failed
decision.status = 'failed'
decision.failed_at = Time.current
```

### Rate Limit

```ruby
# Alpaca response:
# { "code": 42910000, "message": "rate limit exceeded" }

# Stored as:
execution.status = 'rejected'
execution.error_message = 'rate limit exceeded'
execution.http_status_code = 429

# NO RETRY - just fail and move to next signal
```

---

## Testing Strategy

### Unit Tests

```ruby
# spec/packs/audit_trail/models/trade_execution_spec.rb
RSpec.describe AuditTrail::TradeExecution do
  describe 'validations' do
    it { should validate_presence_of(:execution_id) }
    it { should validate_inclusion_of(:status).in_array(%w[submitted filled rejected]) }
  end
  
  describe '#success?' do
    it 'returns true for filled status' do
      execution = FactoryBot.build(:trade_execution, status: 'filled')
      expect(execution.success?).to be true
    end
  end
end
```

### Command Tests

```ruby
# spec/packs/audit_trail/commands/execute_trade_decision_spec.rb
RSpec.describe AuditTrail::ExecuteTradeDecision do
  let(:decision) { FactoryBot.create(:trade_decision, status: 'pending') }
  let(:alpaca_service) { instance_double(AlpacaApi::AlpacaService) }
  
  before do
    allow(AlpacaApi::AlpacaService).to receive(:new).and_return(alpaca_service)
  end
  
  context 'when trade is successful' do
    before do
      allow(alpaca_service).to receive(:place_order).and_return(
        {
          'id' => 'order-123',
          'status' => 'filled',
          'filled_qty' => 100,
          'filled_avg_price' => 150.25
        }
      )
    end
    
    it 'creates successful execution and updates decision' do
      command = described_class.call(trade_decision: decision)
      
      expect(command.success?).to be true
      execution = command.trade_execution
      expect(execution.status).to eq 'filled'
      expect(execution.filled_quantity).to eq 100
      expect(decision.reload.status).to eq 'executed'
    end
  end
  
  context 'when trade fails' do
    before do
      allow(alpaca_service).to receive(:place_order).and_return(
        {
          'status' => 'rejected',
          'message' => 'insufficient buying power'
        }
      )
    end
    
    it 'creates failed execution and updates decision' do
      command = described_class.call(trade_decision: decision)
      
      expect(command.success?).to be true  # Command succeeded
      execution = command.trade_execution
      expect(execution.status).to eq 'rejected'
      expect(execution.error_message).to eq 'insufficient buying power'
      expect(decision.reload.status).to eq 'failed'
    end
  end
end
```

### Integration Tests

```ruby
# spec/packs/audit_trail/integration/trade_execution_flow_spec.rb
RSpec.describe 'Trade Execution Flow' do
  it 'executes complete flow: decision → execution → result' do
    # Create decision
    decision_cmd = AuditTrail::CreateTradeDecision.call(
      strategy_name: 'TestStrategy',
      symbol: 'AAPL',
      side: 'buy',
      quantity: 100,
      rationale: { signal_strength: 8.5 }
    )
    
    # Mock Alpaca API
    allow_any_instance_of(AlpacaApi::AlpacaService).to receive(:place_order)
      .and_return({
        'id' => 'order-123',
        'status' => 'filled',
        'filled_qty' => 100,
        'filled_avg_price' => 150.25
      })
    
    # Execute trade
    execution_cmd = AuditTrail::ExecuteTradeDecision.call(
      trade_decision: decision_cmd.trade_decision
    )
    
    # Verify complete audit trail
    decision = decision_cmd.trade_decision.reload
    execution = execution_cmd.trade_execution
    
    expect(decision.status).to eq 'executed'
    expect(execution.status).to eq 'filled'
    expect(execution.api_request_payload).to be_present
    expect(execution.api_response_payload).to be_present
    expect(execution.filled_quantity).to eq 100
  end
end
```

---

## Performance Considerations

**Write Performance:**
- 3 INSERTs per trade: ApiRequest, ApiResponse, TradeExecution
- Typical: <20ms total
- Acceptable for synchronous execution

**Read Performance:**
- Always eager load: `.includes(:api_request_payload, :api_response_payload)`
- Avoid N+1 queries with proper eager loading
- Extracted fields enable fast filtering without JOIN

---

## Success Metrics

- ✅ 100% of trade attempts logged (both success and failure)
- ✅ Zero JSONB in TradeExecution table (fully normalized)
- ✅ Can reconstruct full API interaction from FK references
- ✅ No retry logic (preserves signal ordering)
