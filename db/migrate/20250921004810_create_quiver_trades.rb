class CreateQuiverTrades < ActiveRecord::Migration[8.0]
  def change
    create_table :quiver_trades do |t|
      t.string :ticker
      t.string :company
      t.string :trader_name
      t.string :trader_source
      t.date :transaction_date
      t.string :transaction_type
      t.string :trade_size_usd
      t.datetime :disclosed_at

      t.timestamps
    end
  end
end
