require 'rails_helper'

RSpec.describe PerformanceSnapshot, type: :model do
  describe 'validations' do
    subject { FactoryBot.build(:performance_snapshot) }

    it { is_expected.to validate_presence_of(:snapshot_date) }
    it { is_expected.to validate_presence_of(:snapshot_type) }
    it { is_expected.to validate_presence_of(:strategy_name) }
    it { is_expected.to validate_inclusion_of(:snapshot_type).in_array(%w[daily weekly]) }
  end

  describe 'scopes' do
    before do
      FactoryBot.create(:performance_snapshot, snapshot_type: 'daily', snapshot_date: '2025-12-01', strategy_name: 'Enhanced')
      FactoryBot.create(:performance_snapshot, snapshot_type: 'weekly', snapshot_date: '2025-12-08', strategy_name: 'Enhanced')
      FactoryBot.create(:performance_snapshot, snapshot_type: 'daily', snapshot_date: '2025-12-02', strategy_name: 'Simple')
    end

    it 'filters by daily snapshots' do
      expect(PerformanceSnapshot.daily.count).to eq(2)
    end

    it 'filters by weekly snapshots' do
      expect(PerformanceSnapshot.weekly.count).to eq(1)
    end

    it 'filters by strategy' do
      expect(PerformanceSnapshot.by_strategy('Enhanced').count).to eq(2)
      expect(PerformanceSnapshot.by_strategy('Simple').count).to eq(1)
    end

    it 'filters by date range' do
      results = PerformanceSnapshot.between_dates(Date.parse('2025-12-01'), Date.parse('2025-12-02'))
      expect(results.count).to eq(2)
    end
  end

  describe '#to_report_hash' do
    let(:snapshot) do
      FactoryBot.create(:performance_snapshot,
        snapshot_date: Date.parse('2025-12-09'),
        snapshot_type: 'weekly',
        strategy_name: 'Enhanced Congressional',
        total_equity: 105_000.50,
        total_pnl: 5000.50,
        sharpe_ratio: 0.8234,
        max_drawdown_pct: -2.1567,
        win_rate: 68.75,
        total_trades: 25
      )
    end

    it 'returns a hash with all metrics' do
      hash = snapshot.to_report_hash

      expect(hash[:date]).to eq('2025-12-09')
      expect(hash[:type]).to eq('weekly')
      expect(hash[:strategy]).to eq('Enhanced Congressional')
      expect(hash[:equity]).to be_within(0.01).of(105_000.50)
      expect(hash[:pnl]).to be_within(0.01).of(5000.50)
      expect(hash[:sharpe_ratio]).to be_within(0.01).of(0.8234)
      expect(hash[:total_trades]).to eq(25)
    end
  end
end
