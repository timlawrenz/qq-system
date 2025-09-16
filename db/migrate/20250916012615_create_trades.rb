class CreateTrades < ActiveRecord::Migration[8.0]
  def change
    create_table :trades do |t|
      t.references :algorithm, null: false, foreign_key: true
      t.string :symbol, null: false
      t.datetime :executed_at, null: false
      t.string :side, null: false
      t.decimal :quantity, precision: 10, scale: 4, null: false
      t.decimal :price, precision: 10, scale: 4, null: false

      t.timestamps
    end
    
    add_index :trades, :symbol
    add_index :trades, :executed_at
    add_index :trades, :side
  end
end
