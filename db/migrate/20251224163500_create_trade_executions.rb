# frozen_string_literal: true

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

    add_reference :alpaca_orders, :trade_decision, 
                  foreign_key: { to_table: :trade_decisions }
  end
end
