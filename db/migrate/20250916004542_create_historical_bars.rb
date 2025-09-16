class CreateHistoricalBars < ActiveRecord::Migration[8.0]
  def change
    create_table :historical_bars do |t|
      t.string :symbol, null: false
      t.datetime :timestamp, null: false
      t.decimal :open, precision: 10, scale: 4, null: false
      t.decimal :high, precision: 10, scale: 4, null: false
      t.decimal :low, precision: 10, scale: 4, null: false
      t.decimal :close, precision: 10, scale: 4, null: false
      t.integer :volume, null: false

      t.timestamps
    end

    add_index :historical_bars, [:symbol, :timestamp], unique: true, name: 'index_historical_bars_on_symbol_and_timestamp'
  end
end
