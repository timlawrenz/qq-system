class FixQuantityPrecisionInAllTables < ActiveRecord::Migration[8.0]
  def up
    # Fix alpaca_orders.qty: decimal(10,4) → decimal(18,8)
    change_column :alpaca_orders, :qty, :decimal, precision: 18, scale: 8
    
    # Fix trade_executions.filled_quantity: integer → decimal(18,8)
    change_column :trade_executions, :filled_quantity, :decimal, precision: 18, scale: 8
    
    # Fix trades.quantity: decimal(10,4) → decimal(18,8)
    change_column :trades, :quantity, :decimal, precision: 18, scale: 8, null: false
  end

  def down
    # Revert to original types (with data loss warning)
    change_column :alpaca_orders, :qty, :decimal, precision: 10, scale: 4
    change_column :trade_executions, :filled_quantity, :integer
    change_column :trades, :quantity, :decimal, precision: 10, scale: 4, null: false
  end
end
