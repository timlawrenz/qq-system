class CreateCommitteeIndustryMappings < ActiveRecord::Migration[8.0]
  def change
    create_table :committee_industry_mappings do |t|
      t.references :committee, null: false, foreign_key: true
      t.references :industry, null: false, foreign_key: true

      t.timestamps
    end
  end
end
