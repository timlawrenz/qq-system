# Technical Spec: Data Ingestion Logging

**Component**: Data Ingestion Audit Trail  
**Pack**: `packs/audit_trail/`  
**Priority**: Phase 1 (Week 1)

---

## Overview

Track all data fetching operations (cron jobs) to enable:
- Regulatory compliance (prove when data became available)
- Debugging (did the cron job run? what did it fetch?)
- Data quality monitoring (detect API failures)
- Complete audit chain (ingestion → decision → execution)

---

## Database Schema

### 1. `data_ingestion_runs` Table

**Purpose**: Tracks each execution of a rake task.

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
      
      # Error handling
      t.text :error_message
      t.jsonb :error_details
      
      t.timestamps
      
      t.index [:task_name, :started_at]
      t.index [:data_source, :started_at]
      t.index [:status, :started_at]
    end
  end
end
```

### 2. `data_ingestion_run_records` Table (Junction)

**Purpose**: Links ingestion runs to the specific records they created/updated.

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_data_ingestion_run_records.rb
class CreateDataIngestionRunRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :data_ingestion_run_records do |t|
      t.references :data_ingestion_run, null: false, foreign_key: true
      t.references :record, polymorphic: true, null: false
      # record_type: 'QuiverTrade', 'PoliticianProfile', 'Committee', etc.
      # record_id: ID of the specific record
      
      # Operation type
      t.string :operation, null: false
      # Values: 'created', 'updated', 'skipped'
      
      t.timestamps
      
      # Composite indexes for efficient lookups
      t.index [:data_ingestion_run_id, :created_at], 
              name: 'idx_dir_records_on_run_and_time'
      t.index [:record_type, :record_id, :data_ingestion_run_id],
              name: 'idx_dir_records_on_record_and_run',
              unique: true
    end
  end
end
```

### 3. `api_call_logs` Table

**Purpose**: Tracks API calls made during data ingestion (references `api_payloads`).

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_api_call_logs.rb
class CreateApiCallLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :api_call_logs do |t|
      t.references :data_ingestion_run, null: false, foreign_key: true
      
      # References to api_payloads table (STI)
      t.references :api_request_payload, foreign_key: { to_table: :api_payloads }
      t.references :api_response_payload, foreign_key: { to_table: :api_payloads }
      
      # Extracted fields for quick queries
      t.string :endpoint, null: false
      t.integer :http_status_code
      t.integer :duration_ms
      t.integer :rate_limit_remaining
      
      t.timestamps
      
      t.index [:data_ingestion_run_id, :created_at]
      t.index :http_status_code
    end
  end
end
```

---

## Models

### 1. `DataIngestionRun`

```ruby
# packs/audit_trail/app/models/audit_trail/data_ingestion_run.rb
module AuditTrail
  class DataIngestionRun < ApplicationRecord
    self.table_name = 'data_ingestion_runs'
    
    # Associations
    has_many :data_ingestion_run_records, 
             class_name: 'AuditTrail::DataIngestionRunRecord',
             dependent: :destroy
    has_many :api_call_logs, 
             class_name: 'AuditTrail::ApiCallLog',
             dependent: :destroy
    
    # Polymorphic associations for specific record types
    has_many :quiver_trades, through: :data_ingestion_run_records,
             source: :record, source_type: 'QuiverTrade'
    has_many :politician_profiles, through: :data_ingestion_run_records,
             source: :record, source_type: 'PoliticianProfile'
    
    # Validations
    validates :run_id, presence: true, uniqueness: true
    validates :task_name, presence: true
    validates :data_source, presence: true
    validates :status, inclusion: { in: %w[running completed failed] }
    validates :started_at, presence: true
    
    # State machine (using acts_as_state_machine)
    include AASM
    
    aasm column: :status do
      state :running, initial: true
      state :completed
      state :failed
      
      event :complete do
        transitions from: :running, to: :completed
      end
      
      event :fail do
        transitions from: :running, to: :failed
      end
    end
    
    # Scopes
    scope :recent, -> { where('started_at >= ?', 24.hours.ago).order(started_at: :desc) }
    scope :for_task, ->(task_name) { where(task_name: task_name) }
    scope :for_source, ->(data_source) { where(data_source: data_source) }
    scope :successful, -> { where(status: 'completed') }
    scope :failed_runs, -> { where(status: 'failed') }
    
    # Instance methods
    def duration_seconds
      return nil unless completed_at || failed_at
      ((completed_at || failed_at) - started_at).to_i
    end
    
    def success?
      status == 'completed'
    end
  end
end
```

### 2. `DataIngestionRunRecord`

```ruby
# packs/audit_trail/app/models/audit_trail/data_ingestion_run_record.rb
module AuditTrail
  class DataIngestionRunRecord < ApplicationRecord
    self.table_name = 'data_ingestion_run_records'
    
    belongs_to :data_ingestion_run, class_name: 'AuditTrail::DataIngestionRun'
    belongs_to :record, polymorphic: true
    
    # Validations
    validates :operation, inclusion: { in: %w[created updated skipped] }
    
    # Scopes
    scope :created_records, -> { where(operation: 'created') }
    scope :updated_records, -> { where(operation: 'updated') }
    scope :skipped_records, -> { where(operation: 'skipped') }
  end
end
```

### 3. `ApiCallLog`

```ruby
# packs/audit_trail/app/models/audit_trail/api_call_log.rb
module AuditTrail
  class ApiCallLog < ApplicationRecord
    self.table_name = 'api_call_logs'
    
    belongs_to :data_ingestion_run, class_name: 'AuditTrail::DataIngestionRun'
    belongs_to :api_request_payload, class_name: 'AuditTrail::ApiRequest',
               foreign_key: 'api_request_payload_id', optional: true
    belongs_to :api_response_payload, class_name: 'AuditTrail::ApiResponse',
               foreign_key: 'api_response_payload_id', optional: true
    
    validates :endpoint, presence: true
    
    # Scopes
    scope :successful, -> { where('http_status_code >= 200 AND http_status_code < 300') }
    scope :failed, -> { where('http_status_code >= 400') }
    
    def success?
      http_status_code&.between?(200, 299)
    end
  end
end
```

---

## GLCommand: LogDataIngestion

```ruby
# packs/audit_trail/app/commands/audit_trail/log_data_ingestion.rb
module AuditTrail
  class LogDataIngestion < GLCommand
    # @param task_name [String] e.g., "data_fetch:congress_daily"
    # @param data_source [String] e.g., "quiverquant_congress"
    # @param block [Proc] The actual fetching logic to execute
    
    def call
      run = create_run_record
      context.run = run
      
      begin
        # Execute the actual fetch logic (passed as block)
        result = yield(run) if block_given?
        
        # Update run with results
        update_run_success(run, result)
        
        context.run = run.reload
        
      rescue StandardError => e
        update_run_failure(run, e)
        raise e
      end
    end
    
    private
    
    def create_run_record
      DataIngestionRun.create!(
        run_id: SecureRandom.uuid,
        task_name: context.task_name,
        data_source: context.data_source,
        started_at: Time.current,
        status: 'running'
      )
    end
    
    def update_run_success(run, result)
      run.update!(
        completed_at: Time.current,
        status: 'completed',
        records_fetched: result[:fetched] || 0,
        records_created: result[:created] || 0,
        records_updated: result[:updated] || 0,
        records_skipped: result[:skipped] || 0,
        data_date_start: result[:date_range]&.first,
        data_date_end: result[:date_range]&.last
      )
      
      # Create junction records
      create_run_records(run, result)
      
      # Create API call logs
      create_api_call_logs(run, result)
      
      Rails.logger.info("✅ #{run.task_name} completed: #{result[:created]} new, #{result[:updated]} updated")
    end
    
    def update_run_failure(run, error)
      run.update!(
        failed_at: Time.current,
        status: 'failed',
        error_message: error.message,
        error_details: {
          backtrace: error.backtrace&.first(10),
          class: error.class.name
        }
      )
      
      Rails.logger.error("❌ #{run.task_name} failed: #{error.message}")
    end
    
    def create_run_records(run, result)
      return unless result[:record_operations]
      
      result[:record_operations].each do |op|
        DataIngestionRunRecord.create!(
          data_ingestion_run: run,
          record: op[:record],
          operation: op[:operation]  # 'created', 'updated', 'skipped'
        )
      end
    end
    
    def create_api_call_logs(run, result)
      return unless result[:api_calls]
      
      result[:api_calls].each do |call|
        # Store request/response as ApiPayload (STI)
        request_payload = ApiRequest.create!(
          payload: call[:request],
          source: context.data_source,
          captured_at: call[:timestamp]
        )
        
        response_payload = ApiResponse.create!(
          payload: call[:response],
          source: context.data_source,
          captured_at: call[:timestamp]
        ) if call[:response]
        
        ApiCallLog.create!(
          data_ingestion_run: run,
          api_request_payload: request_payload,
          api_response_payload: response_payload,
          endpoint: call[:endpoint],
          http_status_code: call[:status_code],
          duration_ms: call[:duration_ms],
          rate_limit_remaining: call[:rate_limit_remaining]
        )
      end
    end
  end
end
```

---

## Usage in Rake Tasks

### Updated `data_fetch:congress_daily`

```ruby
# lib/tasks/data_fetch.rake
namespace :data_fetch do
  desc "Fetch daily congressional trades with audit logging"
  task congress_daily: :environment do
    # Use GLCommand for logging
    command = AuditTrail::LogDataIngestion.call(
      task_name: 'data_fetch:congress_daily',
      data_source: 'quiverquant_congress'
    ) do |run|
      # Original fetch logic
      fetcher = DataFetching::QuiverDataFetchService.new
      result = fetcher.fetch_congressional_trades(days_back: 7)
      
      # Must return hash with expected keys
      {
        fetched: result[:total_fetched],
        created: result[:new_records].count,
        updated: result[:updated_records].count,
        skipped: result[:skipped_records].count,
        date_range: [Date.today - 7.days, Date.today],
        record_operations: result[:operations],  # Array of { record:, operation: }
        api_calls: result[:api_calls]  # Array of { endpoint:, request:, response:, ... }
      }
    end
    
    if command.success?
      puts "✅ Congress data ingestion completed (run_id: #{command.run.run_id})"
      puts "   Records: #{command.run.records_created} created, #{command.run.records_updated} updated"
    else
      puts "❌ Congress data ingestion failed: #{command.failure_message}"
      exit 1
    end
  end
end
```

---

## Query Examples

### Find what data was available at decision time

```ruby
# When creating a TradeDecision, link to recent ingestion runs
recent_runs = AuditTrail::DataIngestionRun
  .successful
  .where('completed_at >= ?', 24.hours.ago)
  .where(data_source: 'quiverquant_congress')
  .order(completed_at: :desc)
  .limit(5)

# Get specific QuiverTrades ingested
quiver_trades = recent_runs.first.quiver_trades
```

### Find which ingestion run created a specific record

```ruby
quiver_trade = QuiverTrade.find(12345)
run_record = AuditTrail::DataIngestionRunRecord
  .where(record: quiver_trade)
  .first

puts "Ingested at: #{run_record.data_ingestion_run.completed_at}"
puts "Task: #{run_record.data_ingestion_run.task_name}"
puts "Operation: #{run_record.operation}"
```

### Monitor data quality

```ruby
# Alert if no records fetched
recent_run = AuditTrail::DataIngestionRun
  .for_task('data_fetch:congress_daily')
  .recent
  .first

if recent_run.records_fetched == 0
  Alert.create!(
    level: 'warning',
    message: "No congressional trades fetched today - API issue?"
  )
end
```

---

## Testing Strategy

### Unit Tests

```ruby
# spec/packs/audit_trail/commands/log_data_ingestion_spec.rb
RSpec.describe AuditTrail::LogDataIngestion do
  describe '#call' do
    it 'creates a DataIngestionRun record' do
      expect {
        described_class.call(
          task_name: 'test_task',
          data_source: 'test_source'
        ) { { fetched: 10, created: 5, updated: 3, skipped: 2 } }
      }.to change(AuditTrail::DataIngestionRun, :count).by(1)
    end
    
    it 'handles exceptions and marks run as failed' do
      command = described_class.call(
        task_name: 'test_task',
        data_source: 'test_source'
      ) { raise StandardError, "API error" }
      
      expect(command.success?).to be false
      expect(command.run.status).to eq 'failed'
      expect(command.run.error_message).to eq 'API error'
    end
  end
end
```

### Integration Tests

```ruby
# spec/packs/audit_trail/integration/data_ingestion_logging_spec.rb
RSpec.describe 'Data Ingestion Logging' do
  it 'logs a complete congress data fetch' do
    # Simulate rake task execution
    command = AuditTrail::LogDataIngestion.call(
      task_name: 'data_fetch:congress_daily',
      data_source: 'quiverquant_congress'
    ) do
      # Simulate fetching data
      qt1 = FactoryBot.create(:quiver_trade, ticker: 'AAPL')
      qt2 = FactoryBot.create(:quiver_trade, ticker: 'MSFT')
      
      {
        fetched: 2,
        created: 2,
        updated: 0,
        skipped: 0,
        date_range: [Date.today - 7.days, Date.today],
        record_operations: [
          { record: qt1, operation: 'created' },
          { record: qt2, operation: 'created' }
        ]
      }
    end
    
    expect(command.success?).to be true
    expect(command.run.records_created).to eq 2
    expect(command.run.data_ingestion_run_records.count).to eq 2
    expect(command.run.quiver_trades).to contain_exactly(qt1, qt2)
  end
end
```

---

## Performance Considerations

- **Overhead**: <50ms per rake task (mostly INSERTs)
- **Storage**: ~1KB per run × 3 tasks/day = ~1MB/year
- **Indexes**: All foreign keys indexed for fast lookups
- **Cleanup**: Consider archiving runs older than 2 years

---

## Success Metrics

- ✅ Every rake task execution logged
- ✅ Can query: "What data did we have on Dec 24, 2025 at 9:00 AM?"
- ✅ Can answer: "Which ingestion run created QuiverTrade #12345?"
- ✅ Zero failed ingestions without alerts
