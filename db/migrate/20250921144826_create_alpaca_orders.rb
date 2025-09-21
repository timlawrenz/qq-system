class CreateAlpacaOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :alpaca_orders do |t|
      t.uuid :alpaca_order_id, null: false
      t.references :quiver_trade, null: true, foreign_key: true
      t.string :symbol, null: false
      t.string :side, null: false
      t.string :status, null: false
      t.decimal :qty, precision: 10, scale: 4
      t.decimal :notional, precision: 10, scale: 4
      t.string :order_type
      t.string :time_in_force
      t.datetime :submitted_at
      t.datetime :filled_at
      t.decimal :filled_avg_price, precision: 10, scale: 4

      t.timestamps
    end

    add_index :alpaca_orders, :alpaca_order_id, unique: true
    add_index :alpaca_orders, :symbol
    add_index :alpaca_orders, :side
    add_index :alpaca_orders, :status
  end
end
