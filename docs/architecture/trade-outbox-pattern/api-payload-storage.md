# Technical Spec: API Payload Storage (STI)

**Component**: Centralized API Request/Response Storage  
**Pack**: `packs/audit_trail/`  
**Priority**: Phase 2 (Week 1-2)

---

## Overview

Single-table inheritance (STI) approach for storing all API payloads across the system:
- **Reusable**: Both TradeExecution and DataIngestionRun reference same table
- **Centralized**: All JSONB storage in one place, easier retention policies
- **Extensible**: Easy to add new payload types (Alpaca, QuiverQuant, ProPublica, etc.)
- **Normalized**: Other tables only store extracted fields + FK references

---

## Database Schema

### `api_payloads` Table (STI)

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_api_payloads.rb
class CreateApiPayloads < ActiveRecord::Migration[8.0]
  def change
    create_table :api_payloads do |t|
      # STI discriminator
      t.string :type, null: false
      # Types: 'AuditTrail::ApiRequest', 'AuditTrail::ApiResponse'
      
      # The actual JSON payload
      t.jsonb :payload, null: false, default: {}
      
      # Metadata
      t.string :source, null: false
      # Values: 'alpaca', 'quiverquant', 'propublica'
      t.datetime :captured_at, null: false
      
      t.timestamps
      
      # Indexes
      t.index :type
      t.index :source
      t.index :captured_at
      t.index :payload, using: :gin  # For JSONB queries
    end
  end
end
```

**Why STI?**
- ✅ Both requests and responses share same storage mechanism
- ✅ Can add type-specific behavior (e.g., `ApiRequest#endpoint`, `ApiResponse#success?`)
- ✅ Single retention policy query: `DELETE FROM api_payloads WHERE captured_at < '2023-01-01'`

**Alternatives Considered:**
- ❌ Separate tables (`api_requests`, `api_responses`) - duplicates structure
- ❌ Store JSONB directly in `trade_executions` - not reusable for data ingestion
- ❌ Store in S3 - adds latency, complexity for querying

---

## Models

### Base Model: `ApiPayload`

```ruby
# packs/audit_trail/app/models/audit_trail/api_payload.rb
module AuditTrail
  class ApiPayload < ApplicationRecord
    self.table_name = 'api_payloads'
    
    # STI types: ApiRequest, ApiResponse
    validates :type, presence: true, inclusion: { 
      in: %w[AuditTrail::ApiRequest AuditTrail::ApiResponse] 
    }
    validates :payload, presence: true
    validates :source, presence: true, inclusion: { 
      in: %w[alpaca quiverquant propublica] 
    }
    validates :captured_at, presence: true
    
    # Scopes
    scope :recent, -> { where('captured_at >= ?', 24.hours.ago) }
    scope :for_source, ->(source) { where(source: source) }
    scope :older_than, ->(date) { where('captured_at < ?', date) }
    
    # Class method for bulk cleanup
    def self.purge_old_payloads(before_date:)
      where('captured_at < ?', before_date).delete_all
    end
  end
end
```

### Subclass: `ApiRequest`

```ruby
# packs/audit_trail/app/models/audit_trail/api_request.rb
module AuditTrail
  class ApiRequest < ApiPayload
    # Type-specific validations
    validate :payload_has_required_keys
    
    # Helper methods to access common request fields
    def endpoint
      payload['endpoint']
    end
    
    def http_method
      payload['method']
    end
    
    def params
      payload['params'] || payload['payload']
    end
    
    def headers
      payload['headers']
    end
    
    private
    
    def payload_has_required_keys
      unless payload.key?('endpoint')
        errors.add(:payload, 'must include endpoint')
      end
    end
  end
end
```

### Subclass: `ApiResponse`

```ruby
# packs/audit_trail/app/models/audit_trail/api_response.rb
module AuditTrail
  class ApiResponse < ApiPayload
    # Helper methods to access common response fields
    def status_code
      payload['status_code'] || payload['http_status']
    end
    
    def success?
      status_code&.to_i&.between?(200, 299)
    end
    
    def error?
      status_code&.to_i&.>=(400)
    end
    
    def error_message
      payload['error'] || payload['message'] || payload['detail']
    end
    
    def body
      payload['body'] || payload
    end
    
    # Alpaca-specific helpers
    def order_id
      payload['id']  # Alpaca order ID
    end
    
    def filled_qty
      payload['filled_qty']
    end
    
    def filled_avg_price
      payload['filled_avg_price']
    end
  end
end
```

---

## Usage Patterns

### Pattern 1: Store API Call in TradeExecution

```ruby
# In ExecuteTradeDecision command
def call
  # Build request
  request_data = {
    endpoint: '/v2/orders',
    method: 'POST',
    payload: {
      symbol: context.trade_decision.symbol,
      qty: context.trade_decision.quantity,
      side: context.trade_decision.side,
      type: 'market',
      time_in_force: 'day'
    }
  }
  
  # Store request payload
  api_request = AuditTrail::ApiRequest.create!(
    payload: request_data,
    source: 'alpaca',
    captured_at: Time.current
  )
  
  # Make actual API call
  response = alpaca_client.place_order(request_data[:payload])
  
  # Store response payload
  api_response = AuditTrail::ApiResponse.create!(
    payload: response,
    source: 'alpaca',
    captured_at: Time.current
  )
  
  # Create TradeExecution with references (no JSONB duplication!)
  trade_execution = AuditTrail::TradeExecution.create!(
    trade_decision: context.trade_decision,
    api_request_payload: api_request,
    api_response_payload: api_response,
    # Extracted fields for querying
    filled_quantity: response['filled_qty'],
    filled_avg_price: response['filled_avg_price'],
    http_status_code: 200,
    alpaca_order_id: response['id']
  )
end
```

### Pattern 2: Store API Call in DataIngestion

```ruby
# In QuiverDataFetchService
def fetch_congressional_trades(days_back:)
  api_calls = []
  
  (0..days_back).each do |day|
    date = Date.today - day.days
    endpoint = "/api/v1/congress/#{date}"
    
    # Build request
    request_data = {
      endpoint: endpoint,
      method: 'GET',
      params: { date: date.to_s }
    }
    
    # Store request
    api_request = AuditTrail::ApiRequest.create!(
      payload: request_data,
      source: 'quiverquant',
      captured_at: Time.current
    )
    
    # Make API call
    response = quiver_client.get(endpoint)
    
    # Store response
    api_response = AuditTrail::ApiResponse.create!(
      payload: response,
      source: 'quiverquant',
      captured_at: Time.current
    )
    
    api_calls << {
      request: api_request,
      response: api_response,
      endpoint: endpoint,
      status_code: response['status'] || 200
    }
  end
  
  { api_calls: api_calls, ... }
end
```

---

## Query Examples

### Find all failed API calls in last 24 hours

```ruby
failed_responses = AuditTrail::ApiResponse
  .recent
  .select { |r| r.error? }

# Group by source
failed_responses.group_by(&:source).each do |source, responses|
  puts "#{source}: #{responses.count} failed API calls"
end
```

### Find API call for specific TradeExecution

```ruby
execution = AuditTrail::TradeExecution.find(123)

# Access request
puts "Endpoint: #{execution.api_request_payload.endpoint}"
puts "Method: #{execution.api_request_payload.http_method}"
puts "Params: #{execution.api_request_payload.params}"

# Access response
puts "Status: #{execution.api_response_payload.status_code}"
puts "Success: #{execution.api_response_payload.success?}"
puts "Body: #{execution.api_response_payload.body}"
```

### Audit trail for specific order

```ruby
# Find TradeExecution by Alpaca order ID
execution = AuditTrail::TradeExecution.find_by(alpaca_order_id: 'abc-123')

# Full audit trail
audit = {
  request: {
    timestamp: execution.api_request_payload.captured_at,
    endpoint: execution.api_request_payload.endpoint,
    payload: execution.api_request_payload.payload
  },
  response: {
    timestamp: execution.api_response_payload.captured_at,
    status_code: execution.api_response_payload.status_code,
    payload: execution.api_response_payload.payload
  }
}
```

### Monitor API health by source

```ruby
# Last 24 hours by source
AuditTrail::ApiResponse.recent.group(:source).count
# => { "alpaca" => 120, "quiverquant" => 15, "propublica" => 3 }

# Success rate by source
AuditTrail::ApiResponse.recent.each_with_object(Hash.new { |h, k| h[k] = { success: 0, total: 0 } }) do |response, stats|
  stats[response.source][:total] += 1
  stats[response.source][:success] += 1 if response.success?
end
```

---

## Retention Policy

### Problem
API payloads grow over time (~26MB/year). Need retention policy.

### Solution

```ruby
# lib/tasks/maintenance.rake
namespace :maintenance do
  desc "Purge old API payloads (>2 years)"
  task purge_old_api_payloads: :environment do
    cutoff_date = 2.years.ago
    
    # Count before
    before_count = AuditTrail::ApiPayload.count
    
    # Delete old payloads
    deleted = AuditTrail::ApiPayload.purge_old_payloads(before_date: cutoff_date)
    
    puts "Purged #{deleted} API payloads older than #{cutoff_date}"
    puts "Remaining: #{AuditTrail::ApiPayload.count} payloads"
  end
end
```

**Cron schedule:**
```bash
# Run monthly
0 2 1 * * cd /path/to/app && rake maintenance:purge_old_api_payloads
```

**Impact:**
- ✅ Keeps database size manageable
- ✅ Audit trail still intact (TradeExecution/ApiCallLog records remain, just lose raw payloads after 2 years)
- ⚠️ Consider archiving to S3 before deletion for long-term compliance

---

## Testing Strategy

### Unit Tests

```ruby
# spec/packs/audit_trail/models/api_payload_spec.rb
RSpec.describe AuditTrail::ApiPayload do
  describe 'STI' do
    it 'creates ApiRequest subclass' do
      request = AuditTrail::ApiRequest.create!(
        payload: { endpoint: '/test', method: 'GET' },
        source: 'alpaca',
        captured_at: Time.current
      )
      
      expect(request.type).to eq 'AuditTrail::ApiRequest'
      expect(request.endpoint).to eq '/test'
    end
    
    it 'creates ApiResponse subclass' do
      response = AuditTrail::ApiResponse.create!(
        payload: { status_code: 200, body: {} },
        source: 'alpaca',
        captured_at: Time.current
      )
      
      expect(response.type).to eq 'AuditTrail::ApiResponse'
      expect(response.success?).to be true
    end
  end
  
  describe '.purge_old_payloads' do
    it 'deletes payloads older than cutoff date' do
      old_payload = FactoryBot.create(:api_request, captured_at: 3.years.ago)
      new_payload = FactoryBot.create(:api_request, captured_at: 1.year.ago)
      
      deleted = described_class.purge_old_payloads(before_date: 2.years.ago)
      
      expect(deleted).to eq 1
      expect(described_class.exists?(old_payload.id)).to be false
      expect(described_class.exists?(new_payload.id)).to be true
    end
  end
end
```

### Integration Tests

```ruby
# spec/packs/audit_trail/integration/api_payload_storage_spec.rb
RSpec.describe 'API Payload Storage' do
  it 'stores and retrieves trade execution API calls' do
    decision = FactoryBot.create(:trade_decision)
    
    # Simulate API call storage
    request = AuditTrail::ApiRequest.create!(
      payload: { endpoint: '/v2/orders', method: 'POST', symbol: 'AAPL' },
      source: 'alpaca',
      captured_at: Time.current
    )
    
    response = AuditTrail::ApiResponse.create!(
      payload: { status_code: 200, id: 'order-123', filled_qty: 100 },
      source: 'alpaca',
      captured_at: Time.current
    )
    
    execution = AuditTrail::TradeExecution.create!(
      trade_decision: decision,
      api_request_payload: request,
      api_response_payload: response,
      filled_quantity: 100,
      alpaca_order_id: 'order-123'
    )
    
    # Retrieve and verify
    reloaded = AuditTrail::TradeExecution.find(execution.id)
    expect(reloaded.api_request_payload.endpoint).to eq '/v2/orders'
    expect(reloaded.api_response_payload.success?).to be true
    expect(reloaded.api_response_payload.order_id).to eq 'order-123'
  end
end
```

---

## Migration Path

### Step 1: Create api_payloads table
```bash
rails g migration CreateApiPayloads
rake db:migrate
```

### Step 2: Deploy models
- Deploy ApiPayload base class
- Deploy ApiRequest and ApiResponse subclasses

### Step 3: Update commands to use new pattern
- Update ExecuteTradeDecision to create ApiPayload records
- Update data fetching services to create ApiPayload records

### Step 4: Verify no JSONB columns left
- TradeExecution should only have FK references
- ApiCallLog should only have FK references

---

## Performance Considerations

**Write Performance:**
- 2 extra INSERTs per API call (request + response)
- Typical: <10ms overhead (acceptable)
- Trade execution: 3 total INSERTs (request, response, execution)

**Read Performance:**
- 2 JOINs to get request/response
- Solution: Always eager load: `TradeExecution.includes(:api_request_payload, :api_response_payload)`
- With proper indexing: <5ms overhead

**Storage:**
- Typical payload size: 1-2KB per request/response pair
- 100 trades/day = 200KB/day = ~73MB/year
- Manageable with retention policy

---

## Success Metrics

- ✅ Zero JSONB columns in TradeExecution or ApiCallLog (fully normalized)
- ✅ All API calls stored centrally (both trading and data ingestion)
- ✅ Retention policy running monthly
- ✅ Can query: "Show me all failed Alpaca API calls in December 2025"
