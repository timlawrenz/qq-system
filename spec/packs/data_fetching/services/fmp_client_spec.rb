# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FmpClient do
  let(:client) { described_class.new }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('FMP_API_KEY', nil).and_return('test-fmp-key')
  end

  describe '#fetch_company_profile' do
    it 'parses sector and industry from stable profile payload' do
      response = instance_double(
        Faraday::Response,
        status: 200,
        body: [
          {
            'symbol' => 'AAPL',
            'companyName' => 'Apple Inc.',
            'sector' => 'Technology',
            'industry' => 'Consumer Electronics',
            'cik' => '0000320193',
            'cusip' => '037833100',
            'isin' => 'US0378331005'
          }
        ].to_json
      )

      connection = instance_double(Faraday::Connection)
      allow(connection).to receive(:get).and_return(response)
      allow(client).to receive(:build_connection).and_return(connection)
      client.instance_variable_set(:@connection, connection)

      result = client.fetch_company_profile('AAPL')

      expect(result[:ticker]).to eq('AAPL')
      expect(result[:sector]).to eq('Technology')
      expect(result[:industry]).to eq('Consumer Electronics')
      expect(result[:cik]).to eq('0000320193')
      expect(result[:cusip]).to eq('037833100')
      expect(result[:isin]).to eq('US0378331005')
    end
  end
end
