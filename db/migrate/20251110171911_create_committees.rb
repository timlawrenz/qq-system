class CreateCommittees < ActiveRecord::Migration[8.0]
  def change
    create_table :committees do |t|
      t.string :code
      t.string :name
      t.string :chamber
      t.text :description

      t.timestamps
    end
    add_index :committees, :code, unique: true
  end
end
