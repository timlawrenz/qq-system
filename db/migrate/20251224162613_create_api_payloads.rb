class CreateApiPayloads < ActiveRecord::Migration[8.0]
  def change
    create_table :api_payloads do |t|
      # STI discriminator
      t.string :type, null: false
      
      # The actual JSON payload
      t.jsonb :payload, null: false, default: {}
      
      # Metadata
      t.string :source, null: false
      t.datetime :captured_at, null: false
      
      t.timestamps
      
      # Indexes
      t.index :type
      t.index :source
      t.index :captured_at
      t.index :payload, using: :gin
    end
  end
end
