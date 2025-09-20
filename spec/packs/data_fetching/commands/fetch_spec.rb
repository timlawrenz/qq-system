# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fetch do
  let(:symbols) { %w[AAPL MSFT] }
  let(:start_date) { Date.parse('2024-01-01') }
  let(:end_date) { Date.parse('2024-01-05') }

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
    # Mock FetchAlpacaData command responses
    allow(FetchAlpacaData).to receive(:call!).and_return(
      double(success?: true, bars_data: sample_bars_data, api_errors: [])
    )
  end

  describe '.call' do
    context 'with valid inputs' do
      context 'when no missing data exists' do
        before do
          # Create data for all trading days to simulate no missing data
          weekend_days = [0, 6]
          (start_date..end_date).reject { |date| weekend_days.include?(date.wday) }.each do |date|
            HistoricalBar.create!(
              symbol: 'AAPL',
              timestamp: date.beginning_of_day + 9.5.hours,
              open: 150.0,
              high: 155.0,
              low: 149.0,
              close: 152.0,
              volume: 1000
            )
            HistoricalBar.create!(
              symbol: 'MSFT',
              timestamp: date.beginning_of_day + 9.5.hours,
              open: 250.0,
              high: 255.0,
              low: 249.0,
              close: 252.0,
              volume: 800
            )
          end
        end

        it 'succeeds without making API calls' do
          expect(FetchAlpacaData).not_to receive(:call!)

          result = described_class.call(symbols: symbols, start_date: start_date, end_date: end_date)

          expect(result).to be_success
          expect(result.fetched_bars).to be_empty
        end
      end

      context 'when missing data exists' do
        before do
          # Create partial data - only AAPL for first day
          HistoricalBar.create!(
            symbol: 'AAPL',
            timestamp: start_date.beginning_of_day + 9.5.hours,
            open: 150.0,
            high: 155.0,
            low: 149.0,
            close: 152.0,
            volume: 1000
          )
        end

        it 'fetches and caches missing data using FetchAlpacaData command' do
          expect(FetchAlpacaData).to receive(:call!).at_least(:once).and_return(
            double(success?: true, bars_data: sample_bars_data, api_errors: [])
          )

          result = described_class.call(symbols: symbols, start_date: start_date, end_date: end_date)

          expect(result).to be_success
          expect(result.fetched_bars).not_to be_empty
        end
      end
    end

    context 'with invalid inputs' do
      it 'fails when start date is after end date' do
        result = described_class.call(
          symbols: symbols,
          start_date: Date.parse('2024-01-10'),
          end_date: Date.parse('2024-01-05')
        )

        expect(result).to be_failure
        expect(result.full_error_message).to include('End date must be after or equal to start date')
      end

      it 'fails when end date is in the future' do
        future_date = Date.current + 1.month
        result = described_class.call(symbols: symbols, start_date: start_date, end_date: future_date)

        expect(result).to be_failure
        expect(result.full_error_message).to include('End date cannot be in the future')
      end
    end

    context 'with API errors' do
      before do
        # Create partial data to trigger API calls
        HistoricalBar.create!(
          symbol: 'AAPL',
          timestamp: start_date.beginning_of_day + 9.5.hours,
          open: 150.0,
          high: 155.0,
          low: 149.0,
          close: 152.0,
          volume: 1000
        )
      end

      it 'handles API errors gracefully' do
        allow(FetchAlpacaData).to receive(:call!).and_return(
          double(success?: true, bars_data: [], api_errors: ['API connection failed'])
        )

        result = described_class.call(symbols: ['AAPL'], start_date: start_date, end_date: end_date)

        expect(result).to be_success # Command succeeds even with API errors
        expect(result.api_errors).to include('API connection failed')
      end
    end
  end
end
