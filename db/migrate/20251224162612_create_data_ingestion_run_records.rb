class CreateDataIngestionRunRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :data_ingestion_run_records do |t|
      t.references :data_ingestion_run, null: false, foreign_key: true
      t.references :record, polymorphic: true, null: false
      
      # Operation type
      t.string :operation, null: false
      
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
