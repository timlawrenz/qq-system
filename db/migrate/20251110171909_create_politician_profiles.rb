class CreatePoliticianProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :politician_profiles do |t|
      t.string :name
      t.string :bioguide_id
      t.string :party
      t.string :state
      t.decimal :quality_score
      t.integer :total_trades
      t.integer :winning_trades
      t.decimal :average_return
      t.datetime :last_scored_at

      t.timestamps
    end
    add_index :politician_profiles, :bioguide_id, unique: true
  end
end
