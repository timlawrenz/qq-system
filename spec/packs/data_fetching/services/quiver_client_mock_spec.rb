# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuiverClient, type: :service do
  let(:client) { described_class.new }
  let(:mock_response) do
    [
      {
        "Ticker" => "AAPL",
        "Company" => "Apple Inc.",
        "Name" => "Nancy Pelosi",
        "Traded" => "2025-01-01",
        "Transaction" => "Purchase",
        "Trade_Size_USD" => "$100,000 - $250,000",
        "Filed" => "2025-01-15T12:00:00Z"
      }
    ]
  end

  before do
    allow(client).to receive(:build_connection).and_return(Faraday.new)
  end

  describe '#fetch_congressional_trades' do
    it 'returns parsed trades on a successful response' do
      allow(client.instance_variable_get(:@connection)).to receive(:get).and_return(
        instance_double(Faraday::Response, status: 200, body: mock_response, headers: { 'Content-Type' => 'application/json' })
      )

      trades = client.fetch_congressional_trades
      expect(trades).to be_an(Array)
      expect(trades.first[:ticker]).to eq("AAPL")
    end

    it 'raises an error on authentication failure' do
      allow(client.instance_variable_get(:@connection)).to receive(:get).and_return(
        instance_double(Faraday::Response, status: 401, body: '{}', headers: { 'Content-Type' => 'application/json' })
      )

      expect { client.fetch_congressional_trades }.to raise_error(StandardError, /authentication failed/)
    end
  end
end
