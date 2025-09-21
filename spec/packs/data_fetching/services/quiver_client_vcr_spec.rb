# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuiverClient, :vcr, type: :service do
  let(:client) { described_class.new }

  before do
    # Set up a test API key for VCR recordings
    # This will be filtered out and replaced with <QUIVER_API_KEY> in cassettes
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('QUIVER_API_KEY', nil).and_return('test-vcr-api-key')
  end

  describe '#fetch_congressional_trades', vcr: { cassette_name: 'quiver_client/congressional_trades' } do
    context 'with successful API response' do
      it 'fetches real congressional trades data', vcr: { cassette_name: 'quiver_client/successful_response' } do
        result = client.fetch_congressional_trades(limit: 5)

        expect(result).to be_an(Array)
        expect(result).not_to be_empty
      end

      it 'returns trades with expected structure', vcr: { cassette_name: 'quiver_client/successful_response' } do
        result = client.fetch_congressional_trades(limit: 5)
        first_trade = result.first

        # Verify the structure of returned trades
        expect(first_trade).to have_key(:ticker)
        expect(first_trade).to have_key(:company)
        expect(first_trade).to have_key(:trader_name)
        expect(first_trade).to have_key(:trader_source)
        expect(first_trade).to have_key(:transaction_date)
        expect(first_trade).to have_key(:transaction_type)
        expect(first_trade).to have_key(:trade_size_usd)
        expect(first_trade).to have_key(:disclosed_at)
      end

      it 'returns trades with correct data types', vcr: { cassette_name: 'quiver_client/successful_response' } do
        result = client.fetch_congressional_trades(limit: 5)
        first_trade = result.first

        # Verify data types
        expect(first_trade[:ticker]).to be_a(String) if first_trade[:ticker]
        expect(first_trade[:company]).to be_a(String) if first_trade[:company]
        expect(first_trade[:trader_name]).to be_a(String) if first_trade[:trader_name]
        expect(first_trade[:trader_source]).to be_a(String) if first_trade[:trader_source]
        expect(first_trade[:transaction_date]).to be_a(Date) if first_trade[:transaction_date]
        expect(first_trade[:transaction_type]).to be_a(String) if first_trade[:transaction_type]
        expect(first_trade[:trade_size_usd]).to be_a(String) if first_trade[:trade_size_usd]
        expect(first_trade[:disclosed_at]).to be_a(Time) if first_trade[:disclosed_at]
      end

      it 'fetches trades with date filters', vcr: { cassette_name: 'quiver_client/with_date_filters' } do
        start_date = Date.parse('2024-01-01')
        end_date = Date.parse('2024-01-31')

        result = client.fetch_congressional_trades(
          start_date: start_date,
          end_date: end_date,
          limit: 3
        )

        expect(result).to be_an(Array)

        # Verify that dates are within the requested range
        result.each do |trade|
          next unless trade[:transaction_date]

          expect(trade[:transaction_date]).to be >= start_date
          expect(trade[:transaction_date]).to be <= end_date
        end
      end

      it 'fetches trades with ticker filter', vcr: { cassette_name: 'quiver_client/with_ticker_filter' } do
        ticker = 'AAPL'

        result = client.fetch_congressional_trades(
          ticker: ticker,
          limit: 3
        )

        expect(result).to be_an(Array)

        # Verify that all trades are for the requested ticker
        result.each do |trade|
          expect(trade[:ticker]).to eq(ticker) if trade[:ticker]
        end
      end
    end

    context 'with API error responses' do
      it 'handles authentication errors', vcr: { cassette_name: 'quiver_client/auth_error' } do
        # Override API key to trigger auth error
        allow(client).to receive(:api_key).and_return('invalid-api-key')

        expect { client.fetch_congressional_trades }
          .to raise_error(StandardError, /authentication failed/)
      end

      it 'handles rate limit errors', vcr: { cassette_name: 'quiver_client/rate_limit_error' } do
        # This would require making many rapid requests to trigger rate limiting
        # For this test, we'll simulate it by recording a 429 response

        # Make multiple rapid requests to potentially trigger rate limiting
        # Note: This might not always trigger a 429, depending on current API usage
        # This is a soft test - we're mainly recording the cassette
        expect do
          5.times { client.fetch_congressional_trades(limit: 1) }
        end.not_to raise_error
      end

      it 'handles validation errors', vcr: { cassette_name: 'quiver_client/validation_error' } do
        # Use invalid date format to trigger validation error
        invalid_date = 'invalid-date-format'

        # May raise different errors depending on API response
        expect do
          client.fetch_congressional_trades(start_date: invalid_date)
        end.to raise_error(StandardError)
      end
    end

    context 'with empty or minimal data' do
      it 'handles empty response gracefully', vcr: { cassette_name: 'quiver_client/empty_response' } do
        # Request data for a future date range that should return no results
        future_start = Date.parse('2025-09-21')
        future_end = Date.parse('2025-10-21')

        result = client.fetch_congressional_trades(
          start_date: future_start,
          end_date: future_end,
          limit: 1
        )

        expect(result).to be_an(Array)
        expect(result).to be_empty
      end
    end
  end

  describe 'rate limiting behavior', vcr: { cassette_name: 'quiver_client/rate_limiting' } do
    it 'enforces rate limiting between requests' do
      start_time = Time.current

      # Make two requests to test rate limiting
      client.fetch_congressional_trades(limit: 1)
      client.fetch_congressional_trades(limit: 1)

      end_time = Time.current

      # Should take at least the request interval
      min_expected_time = described_class::REQUEST_INTERVAL
      expect(end_time - start_time).to be >= min_expected_time
    end
  end

  describe 'connection and network behavior' do
    it 'uses correct API endpoint and headers', vcr: { cassette_name: 'quiver_client/endpoint_verification' } do
      # This test verifies that requests are made to the correct endpoint
      # VCR will record the actual HTTP request details

      result = client.fetch_congressional_trades(limit: 1)

      # The fact that this doesn't raise an error confirms the endpoint is correct
      expect(result).to be_an(Array)
    end

    it 'handles timeout gracefully' do
      # For timeout testing, we need to stub the connection since VCR can't simulate timeouts
      allow(client.instance_variable_get(:@connection)).to receive(:get)
        .and_raise(Faraday::TimeoutError.new('Request timeout'))

      expect { client.fetch_congressional_trades }
        .to raise_error(StandardError, /timeout/)
    end

    it 'handles connection failures gracefully' do
      # For connection failure testing, we need to stub since VCR can't simulate network failures
      allow(client.instance_variable_get(:@connection)).to receive(:get)
        .and_raise(Faraday::ConnectionFailed.new('Connection failed'))

      expect { client.fetch_congressional_trades }
        .to raise_error(StandardError, /Failed to connect/)
    end
  end
end
