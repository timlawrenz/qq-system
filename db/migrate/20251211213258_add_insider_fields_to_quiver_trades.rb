class AddInsiderFieldsToQuiverTrades < ActiveRecord::Migration[8.0]
  def change
    add_column :quiver_trades, :relationship, :string
    add_column :quiver_trades, :shares_held, :bigint
    add_column :quiver_trades, :ownership_percent, :decimal
  end
end
