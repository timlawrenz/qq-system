class AddTradingModeToOrdersAndAnalyses < ActiveRecord::Migration[8.0]
  def change
    add_column :alpaca_orders, :trading_mode, :string, default: 'paper', null: false
    add_column :analyses, :trading_mode, :string, default: 'paper', null: false

    add_index :alpaca_orders, :trading_mode
    add_index :analyses, :trading_mode
  end
end
