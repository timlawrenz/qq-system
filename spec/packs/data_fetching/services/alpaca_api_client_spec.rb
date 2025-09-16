# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlpacaApiClient do
  let(:mock_connection) { instance_double(Faraday::Connection) }
  let(:client) do
    # Stub the connection build in the initialize method
    allow_any_instance_of(described_class).to receive(:build_connection).and_return(mock_connection)
    described_class.new
  end
  let(:symbol) { 'AAPL' }
  let(:start_date) { Date.parse('2024-01-01') }
  let(:end_date) { Date.parse('2024-01-05') }

  before do
    # Stub environment variables for testing
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('ALPACA_API_KEY').and_return('test-api-key')
    allow(ENV).to receive(:[]).with('ALPACA_SECRET_KEY').and_return('test-secret-key')
  end

  describe '#fetch_bars' do
    let(:successful_response) do
      instance_double(
        Faraday::Response,
        status: 200,
        body: {
          'bars' => [
            {
              't' => '2024-01-01T09:30:00Z',
              'o' => 150.0,
              'h' => 155.0,
              'l' => 149.0,
              'c' => 152.0,
              'v' => 1000
            },
            {
              't' => '2024-01-02T09:30:00Z',
              'o' => 152.0,
              'h' => 157.0,
              'l' => 151.0,
              'c' => 154.0,
              'v' => 1200
            }
          ]
        }
      )
    end

    before do
      allow(client).to receive(:rate_limit)
    end

    context 'when API call is successful' do
      before do
        allow(mock_connection).to receive(:get).and_return(successful_response)
      end

      it 'returns formatted bar data' do
        result = client.fetch_bars(symbol, start_date, end_date)

        expect(result).to be_an(Array)
        expect(result.size).to eq(2)

        first_bar = result.first
        expect(first_bar[:symbol]).to eq(symbol)
        expect(first_bar[:timestamp]).to be_a(Time)
        expect(first_bar[:open]).to eq(BigDecimal('150.0'))
        expect(first_bar[:high]).to eq(BigDecimal('155.0'))
        expect(first_bar[:low]).to eq(BigDecimal('149.0'))
        expect(first_bar[:close]).to eq(BigDecimal('152.0'))
        expect(first_bar[:volume]).to eq(1000)
      end

      it 'makes API call with correct parameters' do
        expected_params = {
          start: '2024-01-01',
          end: '2024-01-05',
          timeframe: '1Day',
          adjustment: 'raw',
          feed: 'iex'
        }

        expect(mock_connection).to receive(:get)
          .with('/v2/stocks/AAPL/bars', expected_params)
          .and_return(successful_response)

        client.fetch_bars(symbol, start_date, end_date)
      end

      it 'applies rate limiting' do
        expect(client).to receive(:rate_limit)
        client.fetch_bars(symbol, start_date, end_date)
      end
    end

    context 'when API returns empty data' do
      let(:empty_response) do
        instance_double(Faraday::Response, status: 200, body: { 'bars' => [] })
      end

      before do
        allow(mock_connection).to receive(:get).and_return(empty_response)
      end

      it 'returns empty array' do
        result = client.fetch_bars(symbol, start_date, end_date)
        expect(result).to eq([])
      end
    end

    context 'when API returns authentication error' do
      let(:auth_error_response) do
        instance_double(Faraday::Response, status: 401, body: { 'message' => 'Unauthorized' })
      end

      before do
        allow(mock_connection).to receive(:get).and_return(auth_error_response)
      end

      it 'raises authentication error' do
        expect { client.fetch_bars(symbol, start_date, end_date) }
          .to raise_error(StandardError, /authentication failed/)
      end
    end

    context 'when API returns rate limit error' do
      let(:rate_limit_response) do
        instance_double(Faraday::Response, status: 429, body: { 'message' => 'Rate limit exceeded' })
      end

      before do
        allow(mock_connection).to receive(:get).and_return(rate_limit_response)
      end

      it 'raises rate limit error' do
        expect { client.fetch_bars(symbol, start_date, end_date) }
          .to raise_error(StandardError, /rate limit exceeded/)
      end
    end

    context 'when API returns validation error' do
      let(:validation_error_response) do
        instance_double(
          Faraday::Response,
          status: 422,
          body: { 'message' => 'Invalid symbol' }
        )
      end

      before do
        allow(mock_connection).to receive(:get).and_return(validation_error_response)
      end

      it 'raises validation error with API message' do
        expect { client.fetch_bars(symbol, start_date, end_date) }
          .to raise_error(StandardError, /Invalid symbol/)
      end
    end

    context 'when network error occurs' do
      before do
        allow(mock_connection).to receive(:get).and_raise(Faraday::TimeoutError.new('Timeout'))
      end

      it 'raises timeout error' do
        expect { client.fetch_bars(symbol, start_date, end_date) }
          .to raise_error(StandardError, /timeout/)
      end
    end
  end

  describe '#rate_limit' do
    it 'enforces minimum interval between requests' do
      # Allow the client to access the private method for testing
      client_class = Class.new(described_class) do
        public :rate_limit
      end
      test_client = client_class.new

      start_time = Time.current
      test_client.rate_limit
      test_client.rate_limit
      end_time = Time.current

      # Should take at least the request interval
      min_expected_time = described_class::REQUEST_INTERVAL
      expect(end_time - start_time).to be >= min_expected_time
    end
  end

  describe 'credential handling' do
    context 'when environment variables are provided' do
      it 'uses environment variables for credentials' do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('ALPACA_API_KEY', nil).and_return('env-api-key')

        # Create a fresh client instance for this test
        test_client = described_class.allocate
        allow(test_client).to receive(:build_connection).and_return(mock_connection)
        test_client.send(:initialize)

        # Access private method through send for testing
        api_key = test_client.send(:api_key)
        expect(api_key).to eq('env-api-key')
      end
    end

    context 'when credentials are missing in production' do
      it 'raises error for missing credentials' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ALPACA_API_KEY').and_return(nil)
        allow(Rails.application.credentials).to receive(:dig).and_return(nil)

        # Create a fresh client instance for this test
        test_client = described_class.allocate
        allow(test_client).to receive(:build_connection).and_return(mock_connection)
        test_client.send(:initialize)

        expect { test_client.send(:api_key) }
          .to raise_error(StandardError, /Missing required Alpaca credential/)
      end
    end

    context 'when in development environment' do
      it 'uses default credentials' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ALPACA_API_KEY').and_return(nil)
        allow(Rails.application.credentials).to receive(:dig).and_return(nil)

        # Create a fresh client instance for this test
        test_client = described_class.allocate
        allow(test_client).to receive(:build_connection).and_return(mock_connection)
        test_client.send(:initialize)

        api_key = test_client.send(:api_key)
        expect(api_key).to eq('test-api-key')
      end
    end
  end
end
