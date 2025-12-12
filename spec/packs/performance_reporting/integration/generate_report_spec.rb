# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass

require 'rails_helper'

RSpec.describe 'Performance Report Generation', type: :integration do
  describe 'generating a manual performance report' do
    let(:start_date) { 30.days.ago.to_date }
    let(:end_date) { Date.current }

    before do
      # Stub AlpacaService to avoid real API calls
      alpaca_service = instance_double(AlpacaService)
      allow(AlpacaService).to receive(:new).and_return(alpaca_service)

      # Mock account equity history (30 days of growth)
      equity_history = (0..29).map do |days_ago|
        date = end_date - days_ago.days
        equity = 100_000 + (days_ago * 100) # Simulated growth
        { timestamp: date, equity: BigDecimal(equity.to_s) }
      end.reverse

      # Mock SPY data for benchmark
      allow(alpaca_service).to receive_messages(account_equity_history: equity_history,
                                                account_equity: BigDecimal('103_000'), get_bars: [])
    end

    it 'successfully generates a performance report' do
      result = GeneratePerformanceReport.call(
        start_date: start_date,
        end_date: end_date,
        strategy_name: 'Test Strategy'
      )

      expect(result).to be_success
      expect(result.report_hash).to be_present
      expect(result.file_path).to match(/tmp\/performance_reports/)
      expect(result.snapshot_id).to be_present
    end

    it 'creates a PerformanceSnapshot record' do
      expect do
        GeneratePerformanceReport.call(
          start_date: start_date,
          end_date: end_date,
          strategy_name: 'Test Strategy'
        )
      end.to change(PerformanceSnapshot, :count).by(1)

      snapshot = PerformanceSnapshot.last
      expect(snapshot.strategy_name).to eq('Test Strategy')
      expect(snapshot.snapshot_date).to eq(end_date)
      expect(snapshot.total_equity).to be_present
    end

    it 'saves a JSON report file' do
      result = GeneratePerformanceReport.call(
        start_date: start_date,
        end_date: end_date,
        strategy_name: 'Test Strategy'
      )

      expect(File.exist?(result.file_path)).to be true

      report_data = JSON.parse(File.read(result.file_path))
      expect(report_data['report_date']).to eq(end_date.to_s)
      expect(report_data['strategy']).to be_present
      expect(report_data['strategy']['name']).to eq('Test Strategy')
    end

    it 'calculates performance metrics' do
      result = GeneratePerformanceReport.call(
        start_date: start_date,
        end_date: end_date,
        strategy_name: 'Test Strategy'
      )

      strategy_data = result.report_hash[:strategy]

      # Should have calculated basic metrics
      expect(strategy_data[:total_equity]).to be_present
      expect(strategy_data[:total_pnl]).to be_present
      expect(strategy_data[:pnl_pct]).to be_present

      # NOTE: Sharpe/volatility may be nil with insufficient data (< 30 days)
      # Max drawdown should be calculated
      expect(strategy_data[:max_drawdown_pct]).to be_present
    end

    context 'with insufficient data' do
      it 'handles gracefully and includes warnings' do
        result = GeneratePerformanceReport.call(
          start_date: 15.days.ago.to_date,
          end_date: end_date,
          strategy_name: 'Test Strategy'
        )

        expect(result).to be_success
        expect(result.report_hash[:warnings]).to be_present
        expect(result.report_hash[:warnings]).to include(a_string_matching(/Limited data/))
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
