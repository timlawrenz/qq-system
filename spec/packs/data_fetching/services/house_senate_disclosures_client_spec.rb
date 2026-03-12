# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HouseSenateDisclosuresClient do
  subject(:client) { described_class.new }

  let(:house_payload) do
    [
      {
        'disclosure_year' => 2024,
        'disclosure_date' => '01/20/2024',
        'transaction_date' => '2024-01-15',
        'owner' => 'self',
        'ticker' => 'AAPL',
        'asset_description' => 'Apple, Inc.',
        'asset_type' => 'Stock',
        'type' => 'purchase',
        'amount' => '$1,001 - $15,000',
        'representative' => 'PELOSI, NANCY',
        'district' => 'CA-12',
        'link' => 'https://disclosures.house.gov/public_disc/ptr-pdfs/2024/20240120000001.pdf',
        'capital_gains_over_200_usd' => 'N'
      },
      {
        'disclosure_year' => 2024,
        'disclosure_date' => '01/22/2024',
        'transaction_date' => '2024-01-18',
        'owner' => 'self',
        'ticker' => 'TSLA',
        'asset_description' => 'Tesla, Inc.',
        'asset_type' => 'Stock',
        'type' => 'Sale',
        'amount' => '$15,001 - $50,000',
        'representative' => 'SMITH, JOHN',
        'district' => 'TX-10',
        'link' => 'https://disclosures.house.gov/public_disc/ptr-pdfs/2024/20240122000002.pdf',
        'capital_gains_over_200_usd' => 'N'
      }
    ].to_json
  end

  let(:senate_payload) do
    [
      {
        'transaction_date' => '2024-01-16T00:00:00',
        'owner' => 'self',
        'ticker' => 'MSFT',
        'asset_description' => 'Microsoft Corp.',
        'asset_type' => 'Stock',
        'type' => 'Purchase',
        'amount' => '$50,001 - $100,000',
        'senator' => 'Doe, Jane',
        'disclosure_date' => '01/21/2024',
        'comment' => '',
        'party' => 'D'
      }
    ].to_json
  end

  let(:start_date) { Date.new(2024, 1, 1) }
  let(:end_date)   { Date.new(2024, 1, 31) }

  before do
    # Stub HTTP calls to both S3 endpoints
    stub_request(:get, described_class::HOUSE_DATA_URL)
      .to_return(status: 200, body: house_payload, headers: { 'Content-Type' => 'application/json' })

    stub_request(:get, described_class::SENATE_DATA_URL)
      .to_return(status: 200, body: senate_payload, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#fetch_congressional_trades' do
    subject(:trades) do
      client.fetch_congressional_trades(start_date: start_date, end_date: end_date)
    end

    it 'returns trades from both House and Senate' do
      expect(trades.size).to eq(3)
    end

    it 'sets trader_source to congress for all trades' do
      expect(trades).to all(include(trader_source: 'congress'))
    end

    describe 'House trade parsing' do
      let(:apple_trade) { trades.find { |t| t[:ticker] == 'AAPL' } }

      it 'parses ticker' do
        expect(apple_trade[:ticker]).to eq('AAPL')
      end

      it 'parses company' do
        expect(apple_trade[:company]).to eq('Apple, Inc.')
      end

      it 'parses trader_name' do
        expect(apple_trade[:trader_name]).to eq('PELOSI, NANCY')
      end

      it 'parses transaction_date' do
        expect(apple_trade[:transaction_date]).to eq(Date.new(2024, 1, 15))
      end

      it 'normalizes transaction_type to Purchase' do
        expect(apple_trade[:transaction_type]).to eq('Purchase')
      end

      it 'parses trade_size_usd' do
        expect(apple_trade[:trade_size_usd]).to eq('$1,001 - $15,000')
      end

      it 'parses disclosed_at as a DateTime' do
        expect(apple_trade[:disclosed_at]).to be_a(DateTime)
        expect(apple_trade[:disclosed_at].to_date).to eq(Date.new(2024, 1, 20))
      end

      it 'normalizes Sale type from House data' do
        tesla_trade = trades.find { |t| t[:ticker] == 'TSLA' }
        expect(tesla_trade[:transaction_type]).to eq('Sale')
      end
    end

    describe 'Senate trade parsing' do
      let(:msft_trade) { trades.find { |t| t[:ticker] == 'MSFT' } }

      it 'parses senator name' do
        expect(msft_trade[:trader_name]).to eq('Doe, Jane')
      end

      it 'parses ISO timestamp transaction_date' do
        expect(msft_trade[:transaction_date]).to eq(Date.new(2024, 1, 16))
      end

      it 'parses MM/DD/YYYY disclosure_date' do
        expect(msft_trade[:disclosed_at].to_date).to eq(Date.new(2024, 1, 21))
      end
    end

    context 'with ticker filter' do
      it 'returns only trades for the specified ticker' do
        result = client.fetch_congressional_trades(
          start_date: start_date, end_date: end_date, ticker: 'AAPL'
        )
        expect(result.map { |t| t[:ticker] }).to eq(['AAPL'])
      end
    end

    context 'with limit' do
      it 'caps results at the limit' do
        result = client.fetch_congressional_trades(
          start_date: start_date, end_date: end_date, limit: 1
        )
        expect(result.size).to eq(1)
      end
    end

    context 'when trades fall outside date range' do
      let(:start_date) { Date.new(2024, 3, 1) }
      let(:end_date)   { Date.new(2024, 3, 31) }

      it 'returns no trades' do
        expect(trades).to be_empty
      end
    end

    context 'when non-stock assets are present' do
      let(:house_payload) do
        [
          {
            'disclosure_date' => '01/20/2024',
            'transaction_date' => '2024-01-15',
            'ticker' => 'AAPL',
            'asset_type' => 'Stock Option',
            'type' => 'purchase',
            'amount' => '$1,001 - $15,000',
            'representative' => 'PELOSI, NANCY'
          }
        ].to_json
      end

      it 'filters out non-stock assets' do
        expect(trades.find { |t| t[:ticker] == 'AAPL' }).to be_nil
      end
    end

    context 'when ticker is missing or --' do
      let(:house_payload) do
        [
          {
            'disclosure_date' => '01/20/2024',
            'transaction_date' => '2024-01-15',
            'ticker' => '--',
            'asset_type' => 'Stock',
            'type' => 'purchase',
            'amount' => '$1,001 - $15,000',
            'representative' => 'PELOSI, NANCY'
          }
        ].to_json
      end

      before do
        stub_request(:get, described_class::SENATE_DATA_URL)
          .to_return(status: 200, body: '[]', headers: { 'Content-Type' => 'application/json' })
      end

      it 'skips records without a valid ticker' do
        expect(trades).to be_empty
      end
    end
  end

  describe '#api_calls' do
    it 'records one api_call per source' do
      client.fetch_congressional_trades(start_date: start_date, end_date: end_date)
      expect(client.api_calls.size).to eq(2)
    end

    it 'records the endpoint URLs' do
      client.fetch_congressional_trades(start_date: start_date, end_date: end_date)
      endpoints = client.api_calls.map { |c| c[:endpoint] }
      expect(endpoints).to include(described_class::HOUSE_DATA_URL, described_class::SENATE_DATA_URL)
    end
  end

  context 'when House endpoint returns an error' do
    before do
      stub_request(:get, described_class::HOUSE_DATA_URL)
        .to_return(status: 503, body: 'Service Unavailable')
    end

    it 'returns only Senate trades without raising' do
      result = client.fetch_congressional_trades(start_date: start_date, end_date: end_date)
      expect(result.map { |t| t[:ticker] }).to eq(['MSFT'])
    end
  end

  context 'when Senate endpoint returns an error' do
    before do
      stub_request(:get, described_class::SENATE_DATA_URL)
        .to_return(status: 503, body: 'Service Unavailable')
    end

    it 'returns only House trades without raising' do
      result = client.fetch_congressional_trades(start_date: start_date, end_date: end_date)
      expect(result.map { |t| t[:ticker] }).to contain_exactly('AAPL', 'TSLA')
    end
  end
end
