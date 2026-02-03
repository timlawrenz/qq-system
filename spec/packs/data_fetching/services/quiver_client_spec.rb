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
              'Ticker' => 'AAPL',
              'Company' => 'Apple Inc.',
              'Name' => 'John Doe',
              'Source' => 'congress',
              'Traded' => '2024-01-15',
              'Transaction' => 'Purchase',
              'Trade_Size_USD' => '$1,000 - $15,000',
              'Filed' => '2024-01-20T10:30:00Z'
            },
            {
              'Ticker' => 'TSLA',
              'Company' => 'Tesla, Inc.',
              'Name' => 'Jane Smith',
              'Source' => 'congress',
              'Traded' => '2024-01-16',
              'Transaction' => 'Sale',
              'Trade_Size_USD' => '$15,001 - $50,000',
              'Filed' => '2024-01-21T14:45:00Z'
            }
          ]
        }.to_json, # Convert to JSON string
        headers: { 'Content-Type' => 'application/json' }
      )
    end

    before do
      allow(mock_connection).to receive(:get).and_return(successful_response)
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

        client.fetch_congressional_trades(options)

        expect(mock_connection).to have_received(:get)
          .with('/beta/bulk/congresstrading', expected_params)
      end

      it 'applies default limit when not specified' do
        expected_params = { limit: 100 }

        allow(mock_connection).to receive(:get).and_return(successful_response)

        client.fetch_congressional_trades

        expect(mock_connection).to have_received(:get)
          .with('/beta/bulk/congresstrading', expected_params)
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
              'Ticker' => 'MSFT',
              'Company' => 'Microsoft Corporation',
              'Name' => 'Bob Johnson',
              'Source' => 'congress',
              'Traded' => '2024-01-10',
              'Transaction' => 'Purchase',
              'Trade_Size_USD' => '$50,001 - $100,000',
              'Filed' => '2024-01-15T09:15:00Z'
            }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
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
                'Ticker' => 'GOOGL',
                'Company' => 'Alphabet Inc.',
                'Name' => 'Sarah Wilson'
                # Missing other fields
              }
            ]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
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
          body: { 'data' => [] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
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
          body: { 'message' => 'Invalid API key' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
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
          body: { 'message' => 'Access denied' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
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
          body: { 'message' => 'Invalid date format' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
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
          body: { 'message' => 'Rate limit exceeded' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
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

  describe '#fetch_insider_trades' do
    let(:insider_response) do
      instance_double(
        Faraday::Response,
        status: 200,
        body: [
          {
            'Ticker' => 'AAPL',
            'Name' => 'Tim Cook',
            'Date' => '2024-01-10',
            'AcquiredDisposedCode' => 'A',
            'TransactionCode' => 'P',
            'Shares' => '1000',
            'PricePerShare' => '150.0',
            'fileDate' => '2024-01-12T15:30:00Z',
            'officerTitle' => 'CEO',
            'SharesOwnedFollowing' => '2000'
          },
          {
            # Missing required fields should be skipped
            'Ticker' => nil,
            'Name' => '',
            'Date' => nil
          }
        ].to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    end

    before do
      allow(client).to receive(:rate_limit)
      allow(mock_connection).to receive(:get).and_return(insider_response)
    end

    it 'calls the insider endpoint with correct path and params' do
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

      client.fetch_insider_trades(options)

      expect(mock_connection).to have_received(:get)
        .with('/beta/live/insiders', expected_params)
    end

    it 'parses insider trades with relationship and holdings' do
      result = client.fetch_insider_trades(limit: 10)

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)

      trade = result.first
      expect(trade[:ticker]).to eq('AAPL')
      expect(trade[:trader_name]).to eq('Tim Cook')
      expect(trade[:trader_source]).to eq('insider')
      expect(trade[:transaction_date]).to eq(Date.parse('2024-01-10'))
      expect(trade[:transaction_type]).to eq('Purchase')
      expect(trade[:trade_size_usd].to_f).to eq(150_000.0)
      expect(trade[:disclosed_at]).to eq(Time.zone.parse('2024-01-12T15:30:00Z'))
      expect(trade[:relationship]).to eq('CEO')
      expect(trade[:shares_held]).to eq(2000)
    end
  end

  describe '#fetch_government_contracts' do
    let(:contracts_response) do
      instance_double(
        Faraday::Response,
        status: 200,
        body: [
          {
            'Date' => '2025-12-08',
            'Ticker' => 'LMT',
            'Agency' => 'Department of Defense',
            'Amount' => 150_000_000,
            'Description' => 'F-35 maintenance contract',
            'ContractID' => 'W15P7T-25-C-0001'
          }
        ].to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    end

    before do
      allow(client).to receive(:rate_limit)
      allow(mock_connection).to receive(:get).and_return(contracts_response)
    end

    it 'calls the live govcontracts endpoint when no ticker is provided' do
      client.fetch_government_contracts(limit: 10)

      expect(mock_connection).to have_received(:get)
        .with('/beta/live/govcontracts', {})
    end

    it 'calls the ticker-scoped govcontracts endpoint when ticker is provided' do
      client.fetch_government_contracts(ticker: 'AAPL', limit: 10)

      expect(mock_connection).to have_received(:get)
        .with('/beta/historical/govcontracts/AAPL', { limit: 10 })
    end

    it 'parses contract fields into normalized structure' do
      result = client.fetch_government_contracts(limit: 10)

      expect(result).to be_an(Array)
      expect(result.size).to eq(1)

      contract = result.first
      expect(contract[:contract_id]).to eq('W15P7T-25-C-0001')
      expect(contract[:ticker]).to eq('LMT')
      expect(contract[:agency]).to eq('Department of Defense')
      expect(contract[:contract_value]).to eq(BigDecimal('150000000'))
      expect(contract[:award_date]).to eq(Date.parse('2025-12-08'))
      expect(contract[:description]).to eq('F-35 maintenance contract')
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
        allow(ENV).to receive(:fetch).with('QUIVER_AUTH_TOKEN', nil).and_return('env-api-key')

        # Create a fresh client instance for this test
        test_client = described_class.new

        expect(test_client.send(:api_key)).to eq('env-api-key')
      end
    end

    context 'when Rails credentials are provided' do
      it 'uses Rails credentials when environment variables are not set' do
        allow(ENV).to receive(:fetch).with('QUIVER_AUTH_TOKEN', nil).and_return(nil)
        allow(Rails.application.credentials).to receive(:dig).with(:quiverquant,
                                                                   :auth_token).and_return('credentials-api-key')

        # Create a fresh client instance for this test
        test_client = described_class.new

        expect(test_client.send(:api_key)).to eq('credentials-api-key')
      end
    end

    context 'when no credentials are provided in local environment' do
      it 'uses default credentials with warning' do
        allow(ENV).to receive(:fetch).with('QUIVER_AUTH_TOKEN', nil).and_return(nil)
        allow(Rails.application.credentials).to receive(:dig).with(:quiverquant, :auth_token).and_return(nil)
        allow(Rails.env).to receive(:local?).and_return(true)
        expect(Rails.logger).to receive(:warn).with(/Using default QUIVER_AUTH_TOKEN/)

        # Create a fresh client instance for this test
        test_client = described_class.new

        expect(test_client.send(:api_key)).to eq('test-api-key')
      end
    end

    context 'when no credentials are provided in production' do
      it 'raises an error' do
        allow(ENV).to receive(:fetch).with('QUIVER_AUTH_TOKEN', nil).and_return(nil)
        allow(Rails.application.credentials).to receive(:dig).with(:quiverquant, :auth_token).and_return(nil)
        allow(Rails.env).to receive(:local?).and_return(false)

        expect { described_class.new }
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
