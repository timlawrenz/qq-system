# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnalysePerformance do
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
      before do
        create(:trade,
               algorithm: algorithm,
               symbol: 'AAPL',
               executed_at: Time.zone.parse('2024-01-01 10:00:00'),
               side: 'buy',
               quantity: 100,
               price: 150.0)
        create(:trade,
               algorithm: algorithm,
               symbol: 'AAPL',
               executed_at: Time.zone.parse('2024-01-03 11:00:00'),
               side: 'sell',
               quantity: 100,
               price: 155.0)

        create(:historical_bar,
               symbol: 'AAPL',
               timestamp: Date.parse('2024-01-01'),
               close: 150.0)
        create(:historical_bar,
               symbol: 'AAPL',
               timestamp: Date.parse('2024-01-02'),
               close: 152.0)
        create(:historical_bar,
               symbol: 'AAPL',
               timestamp: Date.parse('2024-01-03'),
               close: 155.0)

        # Mock the Fetch command to succeed
        fetch_context = Fetch.build_context
        allow(Fetch).to receive(:call!).and_return(fetch_context)
      end

      context 'when calculating and returning performance metrics' do
        subject(:result) { described_class.call!(analysis: analysis) }

        let(:results) { result.results }

        it 'succeeds and calls the fetch command' do
          expect(result).to be_success
          expect(Fetch).to have_received(:call!)
        end

        it 'returns all required performance metric keys' do
          expect(results.keys).to contain_exactly(
            :total_pnl, :total_pnl_percentage, :annualized_return, :volatility,
            :sharpe_ratio, :max_drawdown, :calmar_ratio, :win_loss_ratio,
            :portfolio_time_series, :calculated_at
          )
        end

        it 'returns correct data types for key metrics' do
          expect(results[:total_pnl]).to be_a(Numeric)
          expect(results[:portfolio_time_series]).to be_a(Hash)
        end
      end
    end

    context 'when data fetching fails' do
      before do
        create(:trade,
               algorithm: algorithm,
               symbol: 'AAPL',
               executed_at: Time.zone.parse('2024-01-01 10:00:00'))

        # Mock the Fetch command to fail
        fetch_context = Fetch.build_context(error: 'Network error')
        allow(Fetch).to receive(:call!).and_return(fetch_context)
      end

      it 'fails with error message' do
        result = described_class.call(analysis: analysis)

        expect(Fetch).to have_received(:call!)
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
