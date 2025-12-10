class CreateLobbyingExpenditures < ActiveRecord::Migration[8.0]
  def change
    create_table :lobbying_expenditures do |t|
      # Identifiers
      t.string :ticker, null: false
      t.string :quarter, null: false              # Format: "Q4 2025"
      t.date :date, null: false                   # Actual filing date from API
      
      # Financial data
      t.decimal :amount, precision: 15, scale: 2, default: 0.0, null: false
      
      # Metadata - can be duplicated across same ticker/quarter
      # (A company can use multiple lobbying firms per quarter)
      t.string :client                            # e.g., "GOOGLE CLIENT SERVICES"
      t.string :registrant                        # Lobbying firm name
      t.text :issue                               # Lobbying topics (can be long with newlines)
      t.text :specific_issue                      # Detailed issue description

      t.timestamps
      
      # Unique constraint: One record per ticker/quarter/registrant combination
      # Multiple lobbying firms (registrants) can file for same ticker/quarter
      t.index [:ticker, :quarter, :registrant], unique: true, name: 'idx_lobbying_unique'
      
      # Common query indexes
      t.index [:ticker, :quarter], name: 'idx_lobbying_ticker_quarter'
      t.index :ticker, name: 'idx_lobbying_ticker'
      t.index :quarter, name: 'idx_lobbying_quarter'
      t.index :date, name: 'idx_lobbying_date'
    end
  end
end
