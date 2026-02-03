class CreatePoliticianIndustryContributions < ActiveRecord::Migration[8.0]
  def change
    create_table :politician_industry_contributions do |t|
      t.references :politician_profile, null: false, foreign_key: true
      t.references :industry, null: false, foreign_key: true
      
      t.integer :cycle, null: false
      t.decimal :total_amount, precision: 12, scale: 2, default: 0, null: false
      t.integer :contribution_count, default: 0, null: false
      t.integer :employer_count, default: 0, null: false
      
      t.jsonb :top_employers, default: []
      t.datetime :fetched_at
      
      t.timestamps
      
      t.index [:politician_profile_id, :industry_id, :cycle], 
              unique: true, 
              name: 'idx_politician_industry_contributions_unique'
      t.index :cycle
      t.index :total_amount
    end
  end
end
