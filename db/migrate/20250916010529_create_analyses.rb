class CreateAnalyses < ActiveRecord::Migration[8.0]
  def change
    create_table :analyses do |t|
      t.references :algorithm, null: false, foreign_key: true
      t.date :start_date
      t.date :end_date
      t.string :status, default: 'pending'
      t.jsonb :results

      t.timestamps
    end
    
    add_index :analyses, :status
  end
end
