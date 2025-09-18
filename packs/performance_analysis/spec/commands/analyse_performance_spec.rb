# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnalysePerformance, type: :command do
  let(:algorithm) { create(:algorithm) }
  let(:start_date) { Date.parse('2024-01-01') }
  let(:end_date) { Date.parse('2024-01-05') }
  let(:analysis) do
    create(:analysis,
           algorithm: algorithm,
           start_date: start_date,
           end_date: end_date,
           status: 'running')
  end

  describe 'successful execution' do
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

      before do
        # Mock the Fetch command to succeed
        fetch_double = double(success?: true)
        expect(Fetch).to receive(:call!).and_return(fetch_double)
      end

      it 'calculates and returns performance metrics' do
        result = described_class.call!(analysis: analysis)

        expect(result).to be_success
        results = result.results

        expect(results).to have_key(:total_pnl)
        expect(results).to have_key(:total_pnl_percentage)
        expect(results).to have_key(:annualized_return)
        expect(results).to have_key(:volatility)
        expect(results).to have_key(:sharpe_ratio)
        expect(results).to have_key(:max_drawdown)
        expect(results).to have_key(:calmar_ratio)
        expect(results).to have_key(:win_loss_ratio)
        expect(results).to have_key(:portfolio_time_series)
        expect(results).to have_key(:calculated_at)

        expect(results[:total_pnl]).to be_a(Numeric)
        expect(results[:portfolio_time_series]).to be_a(Hash)
      end
    end

    context 'when analysis has no trades' do
      it 'fails with error message' do
        result = described_class.call(analysis: analysis)

        expect(result).to be_failure
        expect(result.error.message).to include('No trades found for algorithm')
      end
    end

    context 'when data fetching fails' do
      let!(:trade) do
        create(:trade,
               algorithm: algorithm,
               symbol: 'AAPL',
               executed_at: Time.zone.parse('2024-01-01 10:00:00'))
      end

      before do
        # Mock the Fetch command to fail
        fetch_double = double(success?: false, error: 'Network error')
        expect(Fetch).to receive(:call!).and_return(fetch_double)
      end

      it 'fails with error message' do
        result = described_class.call(analysis: analysis)

        expect(result).to be_failure
        expect(result.error.message).to include('Failed to fetch market data')
      end
    end
  end

  describe 'parameter validation' do
    it 'requires an Analysis object' do
      result = described_class.call(analysis: 'not_an_analysis')

      expect(result).to be_failure
    end

    it 'fails when analysis parameter is missing' do
      result = described_class.call

      expect(result).to be_failure
    end
  end
end
