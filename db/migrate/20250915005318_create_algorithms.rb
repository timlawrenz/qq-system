# frozen_string_literal: true

class CreateAlgorithms < ActiveRecord::Migration[8.0]
  def change
    create_table :algorithms do |t|
      t.string :name, null: false
      t.text :description

      t.timestamps
    end

    add_index :algorithms, :name
  end
end