class AddFecCommitteeIdToPoliticianProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :politician_profiles, :fec_committee_id, :string
    add_index :politician_profiles, :fec_committee_id
  end
end
