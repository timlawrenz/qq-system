class CreateDataIngestionRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :data_ingestion_runs do |t|
      # Identity
      t.string :run_id, null: false, index: { unique: true }
      t.string :task_name, null: false
      
      # Execution context
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.datetime :failed_at
      t.string :status, null: false, default: "running"
      
      # What was fetched
      t.string :data_source, null: false
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
