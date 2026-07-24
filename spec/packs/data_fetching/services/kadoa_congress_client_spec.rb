# frozen_string_literal: true

require 'rails_helper'

RSpec.describe KadoaCongressClient do
  subject(:client) { described_class.new }

  let(:kadoa_payload) do
    [
      {
        'id' => 'house_20034960_g1',
        'source_id' => 'house_clerk',
        'transaction_date' => '2026-07-14',
        'filing_date' => '2026-07-15',
        'ticker' => 'AAPL',
        'asset_name' => 'Apple Inc.',
        'asset_type' => 'ST',
        'transaction_type' => 'Purchase',
        'amount_range_label' => '$15,001 - $50,000',
        'filer_name' => 'Debbie Dingell',
        'branch' => 'congress',
        'chamber' => 'house',
        'party' => 'D',
        'state' => 'MI',
        'office' => 'U.S. Representative · MI-12',
        'doc_url' => 'https://disclosures-clerk.house.gov/public_disc/ptr-pdfs/2026/20034960.pdf'
      },
      {
        'id' => 'senate_abc123_g0',
        'source_id' => 'senate_efd',
        'transaction_date' => '2026-07-13',
        'filing_date' => '2026-07-14',
        'ticker' => 'MSFT',
        'asset_name' => 'Microsoft Corp.',
        'asset_type' => 'ST',
        'transaction_type' => 'Sale (Full)',
        'amount_range_label' => '$50,001 - $100,000',
        'filer_name' => 'Tommy Tuberville',
        'branch' => 'congress',
        'chamber' => 'senate',
        'party' => 'R',
        'state' => 'AL',
        'office' => 'Senator · AL'
      },
      {
        'id' => 'oge_exec_g0',
        'source_id' => 'oge_executive',
        'transaction_date' => '2026-07-12',
        'filing_date' => '2026-07-15',
        'ticker' => 'NVDA',
        'asset_name' => 'NVIDIA Corp.',
        'asset_type' => 'ST',
        'transaction_type' => 'Purchase',
        'amount_range_label' => '$100,001 - $250,000',
        'filer_name' => 'Donald J Trump',
        'branch' => 'executive',
        'chamber' => nil
      },
      {
        'id' => 'house_skip_bond',
        'source_id' => 'house_clerk',
        'transaction_date' => '2026-07-10',
        'filing_date' => '2026-07-12',
        'ticker' => '--',
        'asset_name' => 'Municipal Bond',
        'asset_type' => 'ST',
        'transaction_type' => 'Purchase',
        'amount_range_label' => '$1,001 - $15,000',
        'filer_name' => 'John Smith',
        'branch' => 'congress',
        'chamber' => 'house'
      },
      {
        'id' => 'house_skip_nonstock',
        'source_id' => 'house_clerk',
        'transaction_date' => '2026-07-11',
        'filing_date' => '2026-07-12',
        'ticker' => 'TSLA',
        'asset_name' => 'Tesla Inc.',
        'asset_type' => nil,
        'transaction_type' => 'Sale',
        'amount_range_label' => '$15,001 - $50,000',
        'filer_name' => 'Jane Doe',
        'branch' => 'congress',
        'chamber' => 'house'
      },
      {
        'id' => 'house_skip_exchange',
        'source_id' => 'house_clerk',
        'transaction_date' => '2026-07-10',
        'filing_date' => '2026-07-12',
        'ticker' => 'HON',
        'asset_name' => 'Honeywell International Inc.',
        'asset_type' => 'ST',
        'transaction_type' => 'Exchange',
        'amount_range_label' => '$15,001 - $50,000',
        'filer_name' => 'John Smith',
        'branch' => 'congress',
        'chamber' => 'house'
      }
    ].to_json
  end

  let(:start_date) { Date.new(2026, 7, 1) }
  let(:end_date)   { Date.new(2026, 7, 31) }

  before do
    stub_request(:get, described_class::DATA_URL)
      .to_return(status: 200, body: kadoa_payload,
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe '#fetch_congressional_trades' do
    context 'with chamber: house (default)' do
      subject(:trades) do
        client.fetch_congressional_trades(
          start_date: start_date, end_date: end_date, chamber: 'house'
        )
      end

      it 'returns only House trades' do
        expect(trades.size).to eq(1)
      end

      it 'parses ticker correctly' do
        expect(trades.first[:ticker]).to eq('AAPL')
      end

      it 'parses company name' do
        expect(trades.first[:company]).to eq('Apple Inc.')
      end

      it 'parses trader_name' do
        expect(trades.first[:trader_name]).to eq('Debbie Dingell')
      end

      it 'sets trader_source to congress' do
        expect(trades.first[:trader_source]).to eq('congress')
      end

      it 'parses transaction_date' do
        expect(trades.first[:transaction_date]).to eq(Date.new(2026, 7, 14))
      end

      it 'normalizes transaction_type to Purchase' do
        expect(trades.first[:transaction_type]).to eq('Purchase')
      end

      it 'parses trade_size_usd' do
        expect(trades.first[:trade_size_usd]).to eq('$15,001 - $50,000')
      end

      it 'parses disclosed_at from filing_date' do
        expect(trades.first[:disclosed_at].to_date).to eq(Date.new(2026, 7, 15))
      end
    end

    context 'with chamber: senate' do
      subject(:trades) do
        client.fetch_congressional_trades(
          start_date: start_date, end_date: end_date, chamber: 'senate'
        )
      end

      it 'returns only Senate trades' do
        expect(trades.size).to eq(1)
        expect(trades.first[:ticker]).to eq('MSFT')
      end

      it 'normalizes Sale (Full) to Sale' do
        expect(trades.first[:transaction_type]).to eq('Sale')
      end
    end

    context 'when filtering by ticker' do
      it 'returns only the specified ticker' do
        result = client.fetch_congressional_trades(
          start_date: start_date, end_date: end_date, chamber: 'house', ticker: 'AAPL'
        )
        expect(result.size).to eq(1)
        expect(result.first[:ticker]).to eq('AAPL')
      end
    end

    context 'when out of date range' do
      let(:start_date) { Date.new(2026, 8, 1) }
      let(:end_date)   { Date.new(2026, 8, 31) }

      it 'returns no trades' do
        result = client.fetch_congressional_trades(
          start_date: start_date, end_date: end_date, chamber: 'house'
        )
        expect(result).to be_empty
      end
    end

    context 'with records that should be filtered out' do
      it 'skips non-stock assets' do
        # The TSLA trade with asset_type nil is already filtered
        trades = client.fetch_congressional_trades(
          start_date: start_date, end_date: end_date, chamber: 'house'
        )
        tickers = trades.pluck(:ticker)
        expect(tickers).not_to include('TSLA')
      end

      it 'skips Exchange transactions' do
        trades = client.fetch_congressional_trades(
          start_date: start_date, end_date: end_date, chamber: 'house'
        )
        tickers = trades.pluck(:ticker)
        expect(tickers).not_to include('HON')
      end

      it 'skips records with blank tickers' do
        trades = client.fetch_congressional_trades(
          start_date: start_date, end_date: end_date, chamber: 'house'
        )
        expect(trades.pluck(:ticker)).not_to include('--')
      end
    end
  end

  describe '#api_calls' do
    it 'records one API call' do
      client.fetch_congressional_trades(
        start_date: start_date, end_date: end_date, chamber: 'house'
      )
      expect(client.api_calls.size).to eq(1)
    end

    it 'records the correct endpoint' do
      client.fetch_congressional_trades(
        start_date: start_date, end_date: end_date, chamber: 'house'
      )
      expect(client.api_calls.first[:endpoint]).to eq(described_class::DATA_URL)
    end
  end

  context 'when the endpoint returns an error' do
    before do
      stub_request(:get, described_class::DATA_URL)
        .to_return(status: 503, body: 'Service Unavailable')
    end

    it 'returns an empty array without raising' do
      result = client.fetch_congressional_trades(
        start_date: start_date, end_date: end_date, chamber: 'house'
      )
      expect(result).to be_empty
    end
  end
end
