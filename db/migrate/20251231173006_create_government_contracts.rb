# frozen_string_literal: true

class CreateGovernmentContracts < ActiveRecord::Migration[8.0]
  def change
    create_table :government_contracts do |t|
      t.string :contract_id, null: false
      t.string :ticker, null: false
      t.string :company
      t.decimal :contract_value, precision: 18, scale: 2, null: false
      t.date :award_date, null: false
      t.string :agency
      t.string :contract_type
      t.text :description
      t.datetime :disclosed_at

      t.timestamps
    end

    add_index :government_contracts, :contract_id, unique: true
    add_index :government_contracts, :ticker
    add_index :government_contracts, :award_date
  end
end
