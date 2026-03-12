# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FetchLobbyingData do
  let(:client_double) { instance_double(SenateLdaClient) }

  let(:base_record) do
    {
      ticker: 'AAPL',
      date: Date.parse('2024-04-10'),
      quarter: 'Q1 2024',
      amount: BigDecimal('250000'),
      client: 'Apple Inc.',
      registrant: 'DC Strategies LLC',
      issue: 'TAX, TEC',
      specific_issue: 'Taxation of digital services'
    }
  end

  before do
    allow(SenateLdaClient).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:api_calls).and_return([])
  end

  describe '.call' do
    context 'with a list of tickers' do
      before do
        allow(client_double).to receive(:fetch_lobbying_data).with('AAPL').and_return([base_record])
        allow(client_double).to receive(:fetch_lobbying_data).with('MSFT').and_return([])
      end

      it 'fetches data for each ticker' do
        described_class.call(tickers: %w[AAPL MSFT])

        expect(client_double).to have_received(:fetch_lobbying_data).with('AAPL')
        expect(client_double).to have_received(:fetch_lobbying_data).with('MSFT')
      end

      it 'creates new LobbyingExpenditure records' do
        result = described_class.call(tickers: ['AAPL'])

        expect(result).to be_success
        expect(result.total_records).to eq(1)
        expect(result.new_records).to eq(1)
        expect(result.tickers_processed).to eq(1)
        expect(LobbyingExpenditure.count).to eq(1)
      end
    end

    context 'when deduplicating by ticker + quarter + registrant' do
      before do
        LobbyingExpenditure.create!(
          ticker: 'AAPL',
          quarter: 'Q1 2024',
          date: Date.parse('2024-04-10'),
          registrant: 'DC Strategies LLC',
          amount: 100_000
        )
        allow(client_double).to receive(:fetch_lobbying_data).with('AAPL').and_return([base_record])
      end

      it 'updates the existing record rather than creating a duplicate' do
        result = described_class.call(tickers: ['AAPL'])

        expect(result).to be_success
        expect(result.new_records).to eq(0)
        expect(result.updated_records).to eq(1)
        expect(LobbyingExpenditure.count).to eq(1)
        expect(LobbyingExpenditure.last.amount.to_d).to eq(BigDecimal('250000'))
      end
    end

    context 'when no tickers are provided' do
      it 'returns success with zero records and does not call the client' do
        result = described_class.call

        expect(result).to be_success
        expect(result.total_records).to eq(0)
        expect(SenateLdaClient).not_to have_received(:new)
      end
    end

    context 'when one ticker raises an error' do
      before do
        allow(client_double).to receive(:fetch_lobbying_data).with('FAIL').and_raise(RuntimeError, 'API error')
        allow(client_double).to receive(:fetch_lobbying_data).with('AAPL').and_return([base_record])
      end

      it 'continues processing other tickers and records the failure' do
        result = described_class.call(tickers: %w[FAIL AAPL])

        expect(result).to be_success
        expect(result.tickers_processed).to eq(1)
        expect(result.tickers_failed).to eq(1)
        expect(result.failed_tickers.first[:ticker]).to eq('FAIL')
        expect(LobbyingExpenditure.count).to eq(1)
      end
    end
  end
end
