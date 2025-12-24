# frozen_string_literal: true

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
