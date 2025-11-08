# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnalysePerformanceJob do
  let(:algorithm) { create(:algorithm) }
  let(:start_date) { Date.parse('2024-01-01') }
  let(:end_date) { Date.parse('2024-01-05') }
  let(:analysis) do
    create(:analysis,
           algorithm: algorithm,
           start_date: start_date,
           end_date: end_date,
           status: 'pending')
  end

  describe '#perform' do
    context 'when AnalysePerformance command succeeds' do
      let(:mock_results) do
        {
          'total_pnl' => 5000.0,
          'total_pnl_percentage' => 5.0,
          'sharpe_ratio' => 1.25,
          'max_drawdown' => 2.3,
          'portfolio_time_series' => { '2024-01-01' => 100_000.0, '2024-01-05' => 105_000.0 }
        }
      end

      let(:mock_command_result) { AnalysePerformance.build_context(results: mock_results) }

      before do
        allow(AnalysePerformance).to receive(:call!).and_return(mock_command_result)
      end

      it 'transitions analysis to running then completed' do
        expect(analysis.status).to eq('pending')

        described_class.perform_now(analysis.id)

        analysis.reload
        expect(analysis.status).to eq('completed')
      end

      it 'calls AnalysePerformance command with correct parameters' do
        described_class.perform_now(analysis.id)
        expect(AnalysePerformance).to have_received(:call!).with(analysis: analysis)
      end

      it 'stores the results from the command' do
        described_class.perform_now(analysis.id)

        analysis.reload
        expect(analysis.results).to eq(mock_results)
      end
    end

    context 'when AnalysePerformance command fails' do
      before do
        # Simulate a command failure by raising an error, as call! would do
        allow(AnalysePerformance).to receive(:call!).and_raise(StandardError, 'No trades found')
      end

      it 'marks analysis as failed' do
        described_class.perform_now(analysis.id)

        analysis.reload
        expect(analysis.status).to eq('failed')
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow(AnalysePerformance).to receive(:call!).and_raise(StandardError, 'Unexpected error')
      end

      it 'marks analysis as failed' do
        described_class.perform_now(analysis.id)

        analysis.reload
        expect(analysis.status).to eq('failed')
      end
    end
  end
end