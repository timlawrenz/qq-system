# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations

require 'rails_helper'

RSpec.describe PerformanceSnapshot, type: :model do
  describe 'validations' do
    it 'validates presence of snapshot_date' do
      snapshot = build(:performance_snapshot, snapshot_date: nil)
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:snapshot_date]).to include("can't be blank")
    end

    it 'validates presence of snapshot_type' do
      snapshot = build(:performance_snapshot, snapshot_type: nil)
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:snapshot_type]).to include("can't be blank")
    end

    it 'validates presence of strategy_name' do
      snapshot = build(:performance_snapshot, strategy_name: nil)
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:strategy_name]).to include("can't be blank")
    end

    it 'validates snapshot_type is daily or weekly' do
      snapshot = build(:performance_snapshot, snapshot_type: 'monthly')
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:snapshot_type]).to include('is not included in the list')

      snapshot.snapshot_type = 'daily'
      expect(snapshot).to be_valid

      snapshot.snapshot_type = 'weekly'
      expect(snapshot).to be_valid
    end

    it 'validates uniqueness of snapshot_date scoped to strategy and type' do
      create(:performance_snapshot,
             snapshot_date: Date.parse('2025-12-09'),
             snapshot_type: 'daily',
             strategy_name: 'Enhanced')

      duplicate = build(:performance_snapshot,
                        snapshot_date: Date.parse('2025-12-09'),
                        snapshot_type: 'daily',
                        strategy_name: 'Enhanced')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:snapshot_date]).to include('has already been taken')
    end

    it 'allows same date with different strategy' do
      create(:performance_snapshot,
             snapshot_date: Date.parse('2025-12-09'),
             snapshot_type: 'daily',
             strategy_name: 'Enhanced')

      different_strategy = build(:performance_snapshot,
                                 snapshot_date: Date.parse('2025-12-09'),
                                 snapshot_type: 'daily',
                                 strategy_name: 'Simple')

      expect(different_strategy).to be_valid
    end

    it 'allows same date with different type' do
      create(:performance_snapshot,
             snapshot_date: Date.parse('2025-12-09'),
             snapshot_type: 'daily',
             strategy_name: 'Enhanced')

      different_type = build(:performance_snapshot,
                             snapshot_date: Date.parse('2025-12-09'),
                             snapshot_type: 'weekly',
                             strategy_name: 'Enhanced')

      expect(different_type).to be_valid
    end
  end

  describe 'scopes' do
    before do
      create(:performance_snapshot, snapshot_type: 'daily', snapshot_date: '2025-12-01', strategy_name: 'Enhanced')
      create(:performance_snapshot, snapshot_type: 'weekly', snapshot_date: '2025-12-08', strategy_name: 'Enhanced')
      create(:performance_snapshot, snapshot_type: 'daily', snapshot_date: '2025-12-02', strategy_name: 'Simple')
    end

    it 'filters by daily snapshots' do
      expect(described_class.daily.count).to eq(2)
    end

    it 'filters by weekly snapshots' do
      expect(described_class.weekly.count).to eq(1)
    end

    it 'filters by strategy' do
      expect(described_class.by_strategy('Enhanced').count).to eq(2)
      expect(described_class.by_strategy('Simple').count).to eq(1)
    end

    it 'filters by date range' do
      results = described_class.between_dates(Date.parse('2025-12-01'), Date.parse('2025-12-02'))
      expect(results.count).to eq(2)
    end
  end

  describe '#to_report_hash' do
    let(:snapshot) do
      create(:performance_snapshot,
             snapshot_date: Date.parse('2025-12-09'),
             snapshot_type: 'weekly',
             strategy_name: 'Enhanced Congressional',
             total_equity: 105_000.50,
             total_pnl: 5000.50,
             sharpe_ratio: 0.8234,
             max_drawdown_pct: -2.1567,
             win_rate: 68.75,
             total_trades: 25,
             winning_trades: 17,
             losing_trades: 8,
             volatility: 12.5,
             calmar_ratio: 3.2,
             metadata: { notes: 'test run' })
    end

    it 'returns a hash with all metrics' do
      hash = snapshot.to_report_hash

      expect(hash[:date]).to eq('2025-12-09')
      expect(hash[:type]).to eq('weekly')
      expect(hash[:strategy]).to eq('Enhanced Congressional')
      expect(hash[:equity]).to be_within(0.01).of(105_000.50)
      expect(hash[:pnl]).to be_within(0.01).of(5000.50)
      expect(hash[:sharpe_ratio]).to be_within(0.01).of(0.8234)
      expect(hash[:max_drawdown_pct]).to be_within(0.01).of(-2.1567)
      expect(hash[:win_rate]).to be_within(0.01).of(68.75)
      expect(hash[:total_trades]).to eq(25)
      expect(hash[:winning_trades]).to eq(17)
      expect(hash[:losing_trades]).to eq(8)
      expect(hash[:volatility]).to be_within(0.01).of(12.5)
      expect(hash[:calmar_ratio]).to be_within(0.01).of(3.2)
      expect(hash[:metadata]).to eq({ 'notes' => 'test run' })
    end

    it 'calculates pnl_pct correctly' do
      hash = snapshot.to_report_hash
      # PnL% = (total_pnl / (total_equity - total_pnl)) * 100
      # = (5000.50 / (105000.50 - 5000.50)) * 100
      # = (5000.50 / 100000) * 100 = 5.0005%
      expect(hash[:pnl_pct]).to be_within(0.01).of(5.0)
    end

    it 'handles nil values gracefully' do
      minimal_snapshot = create(:performance_snapshot,
                                snapshot_date: Date.parse('2025-12-09'),
                                snapshot_type: 'daily',
                                strategy_name: 'Test',
                                total_equity: nil,
                                total_pnl: nil,
                                sharpe_ratio: nil)

      hash = minimal_snapshot.to_report_hash

      expect(hash[:equity]).to be_nil
      expect(hash[:pnl]).to be_nil
      expect(hash[:pnl_pct]).to be_nil
      expect(hash[:sharpe_ratio]).to be_nil
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
