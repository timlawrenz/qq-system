# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlpacaApiClient, type: :service do
  let(:client) { described_class.new }
  let(:mock_bars_response) do
    {
      "bars": [
        {
          "t": "2025-01-01T05:00:00Z",
          "o": 150.0,
          "h": 151.0,
          "l": 149.0,
          "c": 150.5,
          "v": 10000
        }
      ]
    }
  end

  before do
    allow(client).to receive(:build_connection).and_return(Faraday.new)
  end

  describe '#fetch_bars' do
    it 'returns parsed bars on a successful response' do
      allow(client.instance_variable_get(:@connection)).to receive(:get).and_return(
        instance_double(Faraday::Response, status: 200, body: mock_bars_response.to_json)
      )

      bars = client.fetch_bars('AAPL', Date.parse('2025-01-01'), Date.parse('2025-01-02'))
      expect(bars).to be_an(Array)
      expect(bars.first[:symbol]).to eq('AAPL')
      expect(bars.first[:open]).to eq(150.0)
    end

    it 'raises an error on authentication failure' do
      allow(client.instance_variable_get(:@connection)).to receive(:get).and_return(
        instance_double(Faraday::Response, status: 401, body: '{"message":"unauthorized"}')
      )

      expect { client.fetch_bars('AAPL', Date.parse('2025-01-01'), Date.parse('2025-01-02')) }.to raise_error(StandardError, /authentication failed/)
    end
  end
end
