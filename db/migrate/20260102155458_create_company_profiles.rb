# frozen_string_literal: true

class CreateCompanyProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :company_profiles do |t|
      t.string :ticker, null: false
      t.string :company_name
      t.string :sector
      t.string :industry
      t.bigint :annual_revenue
      t.string :cik
      t.string :cusip
      t.string :isin
      t.string :source, null: false, default: 'fmp'
      t.datetime :fetched_at, null: false

      t.timestamps
    end

    add_index :company_profiles, :ticker, unique: true
    add_index :company_profiles, :fetched_at
  end
end
