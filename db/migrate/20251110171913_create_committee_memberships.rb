class CreateCommitteeMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :committee_memberships do |t|
      t.references :politician_profile, null: false, foreign_key: true
      t.references :committee, null: false, foreign_key: true
      t.date :start_date
      t.date :end_date

      t.timestamps
    end
  end
end
