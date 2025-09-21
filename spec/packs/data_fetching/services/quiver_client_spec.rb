# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuiverClient do
  let(:mock_connection) { instance_double(Faraday::Connection) }
  let(:client) do
    # Stub the connection build in the initialize method
    described_class.new.tap do |instance|
      allow(instance).to receive(:build_connection).and_return(mock_connection)
      instance.instance_variable_set(:@connection, mock_connection)
    end
  end

  before do
    # Stub environment variables for testing
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('QUIVER_API_KEY', nil).and_return('test-api-key')
  end

  describe '#fetch_congressional_trades' do
    let(:successful_response) do
      instance_double(
        Faraday::Response,
        status: 200,
        body: {
          'data' => [
            {
              'ticker' => 'AAPL',
              'company' => 'Apple Inc.',
              'trader_name' => 'John Doe',
              'trader_source' => 'congress',
              'transaction_date' => '2024-01-15',
              'transaction_type' => 'Purchase',
              'trade_size_usd' => '$1,000 - $15,000',
              'disclosed_at' => '2024-01-20T10:30:00Z'
            },
            {
              'ticker' => 'TSLA',
              'company' => 'Tesla, Inc.',
              'trader_name' => 'Jane Smith',
              'trader_source' => 'congress',
              'transaction_date' => '2024-01-16',
              'transaction_type' => 'Sale',
              'trade_size_usd' => '$15,001 - $50,000',
              'disclosed_at' => '2024-01-21T14:45:00Z'
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

      it 'returns parsed congressional trades data' do
        result = client.fetch_congressional_trades

        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
      end

      it 'parses first trade correctly' do
        result = client.fetch_congressional_trades
        first_trade = result[0]

        expect(first_trade[:ticker]).to eq('AAPL')
        expect(first_trade[:company]).to eq('Apple Inc.')
        expect(first_trade[:trader_name]).to eq('John Doe')
        expect(first_trade[:trader_source]).to eq('congress')
        expect(first_trade[:transaction_date]).to eq(Date.parse('2024-01-15'))
        expect(first_trade[:transaction_type]).to eq('Purchase')
        expect(first_trade[:trade_size_usd]).to eq('$1,000 - $15,000')
        expect(first_trade[:disclosed_at]).to eq(Time.zone.parse('2024-01-20T10:30:00Z'))
      end

      it 'parses second trade correctly' do
        result = client.fetch_congressional_trades
        second_trade = result[1]

        expect(second_trade[:ticker]).to eq('TSLA')
        expect(second_trade[:transaction_type]).to eq('Sale')
      end

      it 'calls the API with correct parameters' do
        options = {
          start_date: Date.parse('2024-01-01'),
          end_date: Date.parse('2024-01-31'),
          ticker: 'AAPL',
          limit: 50
        }

        expected_params = {
          start_date: '2024-01-01',
          end_date: '2024-01-31',
          ticker: 'AAPL',
          limit: 50
        }

        expect(mock_connection).to receive(:get)
          .with('/v1/congressional-trades', expected_params)
          .and_return(successful_response)

        client.fetch_congressional_trades(options)
      end

      it 'applies default limit when not specified' do
        expected_params = { limit: 100 }

        expect(mock_connection).to receive(:get)
          .with('/v1/congressional-trades', expected_params)
          .and_return(successful_response)

        client.fetch_congressional_trades
      end

      it 'enforces rate limiting' do
        expect(client).to receive(:rate_limit)
        client.fetch_congressional_trades
      end
    end

    context 'when API response has no data wrapper' do
      let(:direct_data_response) do
        instance_double(
          Faraday::Response,
          status: 200,
          body: [
            {
              'ticker' => 'MSFT',
              'company' => 'Microsoft Corporation',
              'trader_name' => 'Bob Johnson',
              'trader_source' => 'congress',
              'transaction_date' => '2024-01-10',
              'transaction_type' => 'Purchase',
              'trade_size_usd' => '$50,001 - $100,000',
              'disclosed_at' => '2024-01-15T09:15:00Z'
            }
          ]
        )
      end

      before do
        allow(mock_connection).to receive(:get).and_return(direct_data_response)
      end

      it 'handles direct array response' do
        result = client.fetch_congressional_trades

        expect(result).to be_an(Array)
        expect(result.length).to eq(1)
        expect(result[0][:ticker]).to eq('MSFT')
      end
    end

    context 'when API response has missing fields' do
      let(:incomplete_response) do
        instance_double(
          Faraday::Response,
          status: 200,
          body: {
            'data' => [
              {
                'ticker' => 'GOOGL',
                'company' => 'Alphabet Inc.',
                'trader_name' => 'Sarah Wilson'
                # Missing other fields
              }
            ]
          }
        )
      end

      before do
        allow(mock_connection).to receive(:get).and_return(incomplete_response)
      end

      it 'handles missing fields gracefully' do
        result = client.fetch_congressional_trades

        expect(result).to be_an(Array)
        expect(result.length).to eq(1)

        trade = result[0]
        expect(trade[:ticker]).to eq('GOOGL')
        expect(trade[:company]).to eq('Alphabet Inc.')
        expect(trade[:trader_name]).to eq('Sarah Wilson')
        expect(trade[:trader_source]).to eq('congress') # default value
        expect(trade[:transaction_date]).to be_nil
        expect(trade[:transaction_type]).to be_nil
        expect(trade[:trade_size_usd]).to be_nil
        expect(trade[:disclosed_at]).to be_nil
      end
    end

    context 'when API returns empty response' do
      let(:empty_response) do
        instance_double(
          Faraday::Response,
          status: 200,
          body: { 'data' => [] }
        )
      end

      before do
        allow(mock_connection).to receive(:get).and_return(empty_response)
      end

      it 'returns empty array' do
        result = client.fetch_congressional_trades
        expect(result).to eq([])
      end
    end

    context 'when authentication fails' do
      let(:auth_error_response) do
        instance_double(
          Faraday::Response,
          status: 401,
          body: { 'message' => 'Invalid API key' }
        )
      end

      before do
        allow(mock_connection).to receive(:get).and_return(auth_error_response)
      end

      it 'raises authentication error' do
        expect { client.fetch_congressional_trades }
          .to raise_error(StandardError, /authentication failed/)
      end
    end

    context 'when access is forbidden' do
      let(:forbidden_response) do
        instance_double(
          Faraday::Response,
          status: 403,
          body: { 'message' => 'Access denied' }
        )
      end

      before do
        allow(mock_connection).to receive(:get).and_return(forbidden_response)
      end

      it 'raises access forbidden error' do
        expect { client.fetch_congressional_trades }
          .to raise_error(StandardError, /access forbidden/)
      end
    end

    context 'when validation error occurs' do
      let(:validation_error_response) do
        instance_double(
          Faraday::Response,
          status: 422,
          body: { 'message' => 'Invalid date format' }
        )
      end

      before do
        allow(mock_connection).to receive(:get).and_return(validation_error_response)
      end

      it 'raises validation error with API message' do
        expect { client.fetch_congressional_trades }
          .to raise_error(StandardError, /Invalid date format/)
      end
    end

    context 'when rate limit is exceeded' do
      let(:rate_limit_response) do
        instance_double(
          Faraday::Response,
          status: 429,
          body: { 'message' => 'Rate limit exceeded' }
        )
      end

      before do
        allow(mock_connection).to receive(:get).and_return(rate_limit_response)
      end

      it 'raises rate limit error' do
        expect { client.fetch_congressional_trades }
          .to raise_error(StandardError, /rate limit exceeded/)
      end
    end

    context 'when network error occurs' do
      before do
        allow(mock_connection).to receive(:get).and_raise(Faraday::TimeoutError.new('Timeout'))
      end

      it 'raises timeout error' do
        expect { client.fetch_congressional_trades }
          .to raise_error(StandardError, /timeout/)
      end
    end

    context 'when connection fails' do
      before do
        allow(mock_connection).to receive(:get).and_raise(Faraday::ConnectionFailed.new('Connection failed'))
      end

      it 'raises connection error' do
        expect { client.fetch_congressional_trades }
          .to raise_error(StandardError, /Failed to connect/)
      end
    end
  end

  describe '#rate_limit' do
    it 'enforces minimum interval between requests' do
      # Allow the client to access the private method for testing
      client_class = Class.new(described_class) do
        public :rate_limit
      end

      # Create test client with mocked connection
      test_client = client_class.new.tap do |instance|
        allow(instance).to receive(:build_connection).and_return(mock_connection)
        instance.instance_variable_set(:@connection, mock_connection)
      end

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
        allow(ENV).to receive(:fetch).with('QUIVER_API_KEY', nil).and_return('env-api-key')

        # Create a fresh client instance for this test
        test_client = described_class.allocate
        allow(test_client).to receive(:build_connection).and_return(mock_connection)
        test_client.send(:initialize)

        expect(test_client.send(:api_key)).to eq('env-api-key')
      end
    end

    context 'when Rails credentials are provided' do
      it 'uses Rails credentials when environment variables are not set' do
        allow(ENV).to receive(:fetch).with('QUIVER_API_KEY', nil).and_return(nil)
        allow(Rails.application.credentials).to receive(:dig).with(:quiver,
                                                                   :quiver_api_key).and_return('credentials-api-key')

        # Create a fresh client instance for this test
        test_client = described_class.allocate
        allow(test_client).to receive(:build_connection).and_return(mock_connection)
        test_client.send(:initialize)

        expect(test_client.send(:api_key)).to eq('credentials-api-key')
      end
    end

    context 'when no credentials are provided in local environment' do
      it 'uses default credentials with warning' do
        allow(ENV).to receive(:fetch).with('QUIVER_API_KEY', nil).and_return(nil)
        allow(Rails.application.credentials).to receive(:dig).with(:quiver, :quiver_api_key).and_return(nil)
        allow(Rails.env).to receive(:local?).and_return(true)
        expect(Rails.logger).to receive(:warn).with(/Using default QUIVER_API_KEY/)

        # Create a fresh client instance for this test
        test_client = described_class.allocate
        allow(test_client).to receive(:build_connection).and_return(mock_connection)
        test_client.send(:initialize)

        expect(test_client.send(:api_key)).to eq('test-api-key')
      end
    end

    context 'when no credentials are provided in production' do
      it 'raises an error' do
        allow(ENV).to receive(:fetch).with('QUIVER_API_KEY', nil).and_return(nil)
        allow(Rails.application.credentials).to receive(:dig).with(:quiver, :quiver_api_key).and_return(nil)
        allow(Rails.env).to receive(:local?).and_return(false)

        # Create a fresh client instance for this test
        test_client = described_class.allocate
        allow(test_client).to receive(:build_connection).and_return(mock_connection)
        test_client.send(:initialize)

        expect { test_client.send(:api_key) }
          .to raise_error(StandardError, /Missing required Quiver credential/)
      end
    end
  end

  describe 'date parsing' do
    let(:test_client) do
      client_class = Class.new(described_class) do
        public :parse_date, :parse_datetime
      end
      client_class.new.tap do |instance|
        allow(instance).to receive(:build_connection).and_return(mock_connection)
        instance.instance_variable_set(:@connection, mock_connection)
      end
    end

    describe '#parse_date' do
      it 'parses valid date strings' do
        expect(test_client.parse_date('2024-01-15')).to eq(Date.parse('2024-01-15'))
      end

      it 'returns nil for blank date strings' do
        expect(test_client.parse_date('')).to be_nil
        expect(test_client.parse_date(nil)).to be_nil
      end

      it 'returns nil and logs warning for invalid date strings' do
        expect(Rails.logger).to receive(:warn).with(/Invalid date format/)
        expect(test_client.parse_date('invalid-date')).to be_nil
      end
    end

    describe '#parse_datetime' do
      it 'parses valid datetime strings' do
        result = test_client.parse_datetime('2024-01-15T10:30:00Z')
        expect(result).to eq(Time.zone.parse('2024-01-15T10:30:00Z'))
      end

      it 'returns nil for blank datetime strings' do
        expect(test_client.parse_datetime('')).to be_nil
        expect(test_client.parse_datetime(nil)).to be_nil
      end

      it 'returns nil and logs warning for invalid datetime strings' do
        expect(Rails.logger).to receive(:warn).with(/Invalid datetime format/)
        expect(test_client.parse_datetime('invalid-datetime')).to be_nil
      end
    end
  end
end
