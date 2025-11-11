class CreateIndustries < ActiveRecord::Migration[8.0]
  def change
    create_table :industries do |t|
      t.string :name
      t.string :sector
      t.text :description

      t.timestamps
    end
    add_index :industries, :name, unique: true
  end
end
