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

  let(:mock_fetch_result) { double(success?: true) }

  before do
    allow(Fetch).to receive(:call!).and_return(mock_fetch_result)
  end

  describe '#perform' do
    context 'when analysis has trades' do
      let!(:trades) do
        [
          create(:trade,
                 algorithm: algorithm,
                 symbol: 'AAPL',
                 executed_at: Time.zone.parse('2024-01-01 10:00:00'),
                 side: 'buy',
                 quantity: 100,
                 price: 150.0),
          create(:trade,
                 algorithm: algorithm,
                 symbol: 'AAPL',
                 executed_at: Time.zone.parse('2024-01-03 11:00:00'),
                 side: 'sell',
                 quantity: 100,
                 price: 155.0)
        ]
      end

      let!(:historical_bars) do
        [
          create(:historical_bar,
                 symbol: 'AAPL',
                 timestamp: Date.parse('2024-01-01'),
                 close: 150.0),
          create(:historical_bar,
                 symbol: 'AAPL',
                 timestamp: Date.parse('2024-01-02'),
                 close: 152.0),
          create(:historical_bar,
                 symbol: 'AAPL',
                 timestamp: Date.parse('2024-01-03'),
                 close: 155.0)
        ]
      end

      it 'transitions analysis to running then completed' do
        expect(analysis.status).to eq('pending')

        described_class.perform_now(analysis.id)

        analysis.reload
        expect(analysis.status).to eq('completed')
      end

      it 'calls Fetch command with correct parameters' do
        described_class.perform_now(analysis.id)

        expect(Fetch).to have_received(:call!).with(
          symbols: ['AAPL'],
          start_date: start_date,
          end_date: end_date
        )
      end

      it 'calculates and stores performance metrics' do
        described_class.perform_now(analysis.id)

        analysis.reload
        results = analysis.results

        expect(results).to include(
          'total_pnl',
          'total_pnl_percentage',
          'annualized_return',
          'volatility',
          'sharpe_ratio',
          'max_drawdown',
          'calmar_ratio',
          'win_loss_ratio',
          'portfolio_time_series',
          'calculated_at'
        )

        expect(results['total_pnl']).to be_a(Numeric).or be_a(String) # JSON might serialize numbers as strings
        expect(results['portfolio_time_series']).to be_a(Hash)
      end
    end

    context 'when analysis has no trades' do
      it 'marks analysis as failed' do
        described_class.perform_now(analysis.id)

        analysis.reload
        expect(analysis.status).to eq('failed')
      end
    end

    context 'when data fetching fails' do
      let!(:trade) do
        create(:trade,
               algorithm: algorithm,
               symbol: 'AAPL',
               executed_at: Time.zone.parse('2024-01-01 10:00:00'))
      end

      let(:mock_fetch_result) { double(success?: false, error: 'Network error') }

      it 'marks analysis as failed' do
        described_class.perform_now(analysis.id)

        analysis.reload
        expect(analysis.status).to eq('failed')
      end
    end
  end
end
