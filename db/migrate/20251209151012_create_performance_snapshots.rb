class CreatePerformanceSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :performance_snapshots do |t|
      t.date :snapshot_date, null: false
      t.string :snapshot_type, null: false
      t.string :strategy_name, null: false
      t.decimal :total_equity, precision: 15, scale: 2
      t.decimal :total_pnl, precision: 15, scale: 2
      t.decimal :sharpe_ratio, precision: 10, scale: 4
      t.decimal :max_drawdown_pct, precision: 10, scale: 4
      t.decimal :volatility, precision: 10, scale: 4
      t.decimal :win_rate, precision: 10, scale: 4
      t.integer :total_trades, default: 0
      t.integer :winning_trades, default: 0
      t.integer :losing_trades, default: 0
      t.decimal :calmar_ratio, precision: 10, scale: 4
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :performance_snapshots, :snapshot_date
    add_index :performance_snapshots, :strategy_name
    add_index :performance_snapshots, :snapshot_type
    add_index :performance_snapshots, [:snapshot_date, :strategy_name, :snapshot_type], 
              unique: true, 
              name: 'index_snapshots_on_date_strategy_type'
  end
end
