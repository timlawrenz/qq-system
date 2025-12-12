class AddColumnsToPerformanceSnapshots < ActiveRecord::Migration[8.0]
  def change
    add_column :performance_snapshots, :snapshot_date, :date, null: false
    add_column :performance_snapshots, :snapshot_type, :string, null: false
    add_column :performance_snapshots, :strategy_name, :string, null: false
    add_column :performance_snapshots, :total_equity, :decimal, precision: 15, scale: 2
    add_column :performance_snapshots, :total_pnl, :decimal, precision: 15, scale: 2
    add_column :performance_snapshots, :sharpe_ratio, :decimal, precision: 10, scale: 4
    add_column :performance_snapshots, :max_drawdown_pct, :decimal, precision: 10, scale: 4
    add_column :performance_snapshots, :volatility, :decimal, precision: 10, scale: 4
    add_column :performance_snapshots, :win_rate, :decimal, precision: 10, scale: 4
    add_column :performance_snapshots, :total_trades, :integer, default: 0
    add_column :performance_snapshots, :winning_trades, :integer, default: 0
    add_column :performance_snapshots, :losing_trades, :integer, default: 0
    add_column :performance_snapshots, :calmar_ratio, :decimal, precision: 10, scale: 4
    add_column :performance_snapshots, :metadata, :jsonb, default: {}

    add_index :performance_snapshots, :snapshot_date
    add_index :performance_snapshots, :strategy_name
    add_index :performance_snapshots, :snapshot_type
    add_index :performance_snapshots, [:snapshot_date, :strategy_name, :snapshot_type], 
              unique: true, 
              name: 'index_snapshots_on_date_strategy_type'
  end
end
