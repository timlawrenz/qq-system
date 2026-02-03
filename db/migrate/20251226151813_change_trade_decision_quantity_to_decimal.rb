# frozen_string_literal: true

class ChangeTradeDecisionQuantityToDecimal < ActiveRecord::Migration[8.0]
  def up
    change_column :trade_decisions, :quantity, :decimal, precision: 18, scale: 8, null: false
  end

  def down
    change_column :trade_decisions, :quantity, :integer, null: false
  end
end
