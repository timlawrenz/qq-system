class AddProPublicaFieldsToPoliticianProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :politician_profiles, :propublica_id, :string
    add_column :politician_profiles, :district, :string
    add_column :politician_profiles, :chamber, :string
    
    add_index :politician_profiles, :propublica_id
  end
end
