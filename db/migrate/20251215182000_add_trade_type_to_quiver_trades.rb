class AddTradeTypeToQuiverTrades < ActiveRecord::Migration[8.0]
  def change
    add_column :quiver_trades, :trade_type, :string
  end
end
