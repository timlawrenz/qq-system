class AddProPublicaFieldsToCommittees < ActiveRecord::Migration[8.0]
  def change
    add_column :committees, :propublica_id, :string
    add_column :committees, :url, :string
    add_column :committees, :jurisdiction, :text
    
    add_index :committees, :propublica_id, unique: true
  end
end
