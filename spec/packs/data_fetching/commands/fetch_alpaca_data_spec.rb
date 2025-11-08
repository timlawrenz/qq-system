# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FetchAlpacaData do
  let(:symbol) { 'AAPL' }
  let(:start_date) { Date.parse('2024-01-01') }
  let(:end_date) { Date.parse('2024-01-03') }
  let(:mock_alpaca_client) { instance_double(AlpacaApiClient) }

  let(:sample_bars_data) do
    [
      {
        symbol: 'AAPL',
        timestamp: Time.zone.parse('2024-01-01 09:30:00 UTC'),
        open: BigDecimal('150.0'),
        high: BigDecimal('155.0'),
        low: BigDecimal('149.0'),
        close: BigDecimal('152.0'),
        volume: 1000
      },
      {
        symbol: 'AAPL',
        timestamp: Time.zone.parse('2024-01-02 09:30:00 UTC'),
        open: BigDecimal('152.0'),
        high: BigDecimal('157.0'),
        low: BigDecimal('151.0'),
        close: BigDecimal('154.0'),
        volume: 1200
      }
    ]
  end

  before do
    allow(AlpacaApiClient).to receive(:new).and_return(mock_alpaca_client)
    allow(mock_alpaca_client).to receive(:fetch_bars).and_return(sample_bars_data)
  end

  describe '.call' do
    context 'with valid inputs' do
      it 'fetches data from Alpaca API' do
        allow(mock_alpaca_client).to receive(:fetch_bars).and_return(sample_bars_data)

        result = described_class.call(symbols: [symbol], start_date: start_date, end_date: end_date)

        expect(mock_alpaca_client).to have_received(:fetch_bars)
        expect(result).to be_success
        expect(result.bars_data).to eq(sample_bars_data)
        expect(result.api_errors).to be_empty
      end

      it 'handles empty API response' do
        allow(mock_alpaca_client).to receive(:fetch_bars).and_return([])

        result = described_class.call(symbols: [symbol], start_date: start_date, end_date: end_date)

        expect(result).to be_success
        expect(result.bars_data).to be_empty
        expect(result.api_errors).to be_empty
      end
    end

    context 'with invalid inputs' do
      it 'fails when symbol is missing' do
        result = described_class.call(symbols: '', start_date: start_date, end_date: end_date)

        expect(result).to be_failure
        expect(result.full_error_message).to include("can't be blank")
      end

      it 'fails with invalid symbol format' do
        result = described_class.call(symbols: 'INVALID123', start_date: start_date, end_date: end_date)

        expect(result).to be_failure
        expect(result.full_error_message).to include('Invalid symbols: INVALID123')
      end

      it 'fails when start date is after end date' do
        result = described_class.call(
          symbols: [symbol],
          start_date: Date.parse('2024-01-10'),
          end_date: Date.parse('2024-01-05')
        )

        expect(result).to be_failure
        expect(result.full_error_message).to include('End date must be after or equal to start date')
      end

      it 'fails when end date is in the future' do
        future_date = Date.current + 1.month
        result = described_class.call(symbols: [symbol], start_date: start_date, end_date: future_date)

        expect(result).to be_failure
        expect(result.full_error_message).to include('End date cannot be in the future')
      end
    end

    context 'with API errors' do
      it 'handles API errors gracefully' do
        allow(mock_alpaca_client).to receive(:fetch_bars)
          .and_raise(StandardError.new('API connection failed'))

        result = described_class.call(symbols: [symbol], start_date: start_date, end_date: end_date)

        expect(result).to be_success # Command succeeds even with API errors
        expect(result.api_errors).to include(/API connection failed/)
        expect(result.bars_data).to be_empty
      end
    end
  end
end
