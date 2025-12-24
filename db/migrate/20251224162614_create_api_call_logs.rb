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
