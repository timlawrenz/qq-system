class CreateBlockedAssets < ActiveRecord::Migration[8.0]
  def change
    create_table :blocked_assets do |t|
      t.string :symbol, null: false
      t.string :reason, null: false
      t.datetime :blocked_at, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :blocked_assets, :symbol, unique: true
    add_index :blocked_assets, :expires_at
  end
end
