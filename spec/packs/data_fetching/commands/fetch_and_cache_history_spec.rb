# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FetchAndCacheHistory, type: :command do
  describe '.call' do
    let(:symbols) { %w[AAPL MSFT] }
    let(:start_date) { Date.parse('2024-01-01') }
    let(:end_date) { Date.parse('2024-01-05') }
    let(:mock_alpaca_client) { instance_double(AlpacaApiClient) }

    let(:sample_bars_data) do
      [
        {
          symbol: 'AAPL',
          timestamp: Time.parse('2024-01-01 09:30:00 UTC'),
          open: BigDecimal('150.0'),
          high: BigDecimal('155.0'),
          low: BigDecimal('149.0'),
          close: BigDecimal('152.0'),
          volume: 1000
        },
        {
          symbol: 'AAPL',
          timestamp: Time.parse('2024-01-02 09:30:00 UTC'),
          open: BigDecimal('152.0'),
          high: BigDecimal('157.0'),
          low: BigDecimal('151.0'),
          close: BigDecimal('154.0'),
          volume: 1200
        }
      ]
    end

    before do
      # Mock the Alpaca client using standard RSpec methods
      mock_alpaca_client = instance_double(AlpacaApiClient)
      allow(AlpacaApiClient).to receive(:new).and_return(mock_alpaca_client)
      allow(mock_alpaca_client).to receive(:fetch_bars).and_return(sample_bars_data)
      @mock_alpaca_client = mock_alpaca_client
    end

    context 'with valid inputs' do
      context 'when no missing data exists' do
        before do
          # Create data for all trading days to simulate no missing data
          (start_date..end_date).reject { |date| [0, 6].include?(date.wday) }.each do |date|
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
          expect(@mock_alpaca_client).not_to receive(:fetch_bars)

          result = described_class.call(symbols: symbols, start_date: start_date, end_date: end_date)

          expect(result).to be_success
          expect(result.cached_bars_count).to eq(0)
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

        it 'fetches and caches missing data' do
          # Mock API calls for missing data
          expect(@mock_alpaca_client).to receive(:fetch_bars).at_least(:once).and_return(sample_bars_data)

          result = described_class.call(symbols: symbols, start_date: start_date, end_date: end_date)

          expect(result).to be_success
          expect(result.cached_bars_count).to be > 0
          expect(result.fetched_bars).not_to be_empty
        end
      end
    end

    context 'with invalid inputs' do
      it 'fails when no symbols provided' do
        result = described_class.call(symbols: [], start_date: start_date, end_date: end_date)

        expect(result).to be_failure
        expect(result.error_message).to include('At least one symbol must be provided')
      end

      it 'fails with invalid symbol format' do
        result = described_class.call(symbols: ['INVALID123'], start_date: start_date, end_date: end_date)

        expect(result).to be_failure
        expect(result.error_message).to include('Invalid symbols: INVALID123')
      end

      it 'fails when start date is after end date' do
        result = described_class.call(
          symbols: symbols,
          start_date: Date.parse('2024-01-10'),
          end_date: Date.parse('2024-01-05')
        )

        expect(result).to be_failure
        expect(result.error_message).to include('Start date must be before or equal to end date')
      end

      it 'fails when end date is in the future' do
        future_date = Date.current + 1.month
        result = described_class.call(symbols: symbols, start_date: start_date, end_date: future_date)

        expect(result).to be_failure
        expect(result.error_message).to include('End date cannot be in the future')
      end
    end

    context 'with API errors' do
      before do
        # Mock missing data to trigger API calls
        allow_any_instance_of(described_class).to receive(:find_missing_dates)
          .and_return([Date.parse('2024-01-01')])
      end

      it 'handles API errors gracefully' do
        allow(@mock_alpaca_client).to receive(:fetch_bars)
          .and_raise(StandardError.new('API connection failed'))

        result = described_class.call(symbols: ['AAPL'], start_date: start_date, end_date: end_date)

        expect(result).to be_success # Command succeeds even with API errors
        expect(result.errors).to include(/API connection failed/)
        expect(result.cached_bars_count).to eq(0)
      end
    end
  end

  describe 'symbol validation' do
    subject { described_class.new(symbols: symbols, start_date: Date.current, end_date: Date.current) }

    context 'with valid symbols' do
      let(:symbols) { %w[AAPL MSFT] }

      it 'accepts valid symbols' do
        expect(subject.send(:valid_symbol?, 'AAPL')).to be(true)
        expect(subject.send(:valid_symbol?, 'MSFT')).to be(true)
      end
    end

    context 'with invalid symbols' do
      let(:symbols) { ['INVALID123'] }

      it 'rejects symbols with numbers' do
        expect(subject.send(:valid_symbol?, 'INVALID123')).to be(false)
      end

      it 'rejects symbols that are too long' do
        expect(subject.send(:valid_symbol?, 'TOOLONG')).to be(false)
      end

      it 'rejects lowercase symbols' do
        expect(subject.send(:valid_symbol?, 'aapl')).to be(false)
      end
    end
  end

  describe 'date grouping' do
    subject { described_class.new(symbols: ['AAPL'], start_date: Date.current, end_date: Date.current) }

    it 'groups consecutive dates into ranges' do
      dates = [
        Date.parse('2024-01-01'),
        Date.parse('2024-01-02'),
        Date.parse('2024-01-03'),
        Date.parse('2024-01-05'),
        Date.parse('2024-01-08'),
        Date.parse('2024-01-09')
      ]

      ranges = subject.send(:group_consecutive_dates, dates)

      expected_ranges = [
        [Date.parse('2024-01-01'), Date.parse('2024-01-03')],
        [Date.parse('2024-01-05'), Date.parse('2024-01-05')],
        [Date.parse('2024-01-08'), Date.parse('2024-01-09')]
      ]

      expect(ranges).to eq(expected_ranges)
    end

    it 'handles single date' do
      dates = [Date.parse('2024-01-01')]
      ranges = subject.send(:group_consecutive_dates, dates)

      expect(ranges).to eq([[Date.parse('2024-01-01'), Date.parse('2024-01-01')]])
    end

    it 'handles empty array' do
      ranges = subject.send(:group_consecutive_dates, [])
      expect(ranges).to eq([])
    end
  end

  describe 'missing data detection' do
    subject { described_class.new(symbols: ['AAPL'], start_date: start_date, end_date: end_date) }
    let(:start_date) { Date.parse('2024-01-01') } # Monday
    let(:end_date) { Date.parse('2024-01-05') }   # Friday

    it 'identifies missing weekdays' do
      # Create some existing data
      HistoricalBar.create!(
        symbol: 'AAPL',
        timestamp: Time.zone.parse('2024-01-01 09:30:00'),
        open: 150.0,
        high: 155.0,
        low: 149.0,
        close: 152.0,
        volume: 1000
      )

      missing_dates = subject.send(:find_missing_dates, 'AAPL')

      # Should find missing trading days (excluding weekends)
      expected_missing = [
        Date.parse('2024-01-02'), # Tuesday
        Date.parse('2024-01-03'), # Wednesday
        Date.parse('2024-01-04'), # Thursday
        Date.parse('2024-01-05')  # Friday
      ]

      expect(missing_dates).to match_array(expected_missing)
    end

    it 'excludes weekends from missing dates' do
      # Jan 6-7, 2024 are Saturday and Sunday
      weekend_subject = described_class.new(
        symbols: ['AAPL'],
        start_date: Date.parse('2024-01-06'),
        end_date: Date.parse('2024-01-07')
      )

      missing_dates = weekend_subject.send(:find_missing_dates, 'AAPL')
      expect(missing_dates).to be_empty
    end

    it 'returns empty array when all data exists' do
      # Create data for all trading days
      (start_date..end_date).reject { |date| [0, 6].include?(date.wday) }.each do |date|
        HistoricalBar.create!(
          symbol: 'AAPL',
          timestamp: date.beginning_of_day + 9.5.hours,
          open: 150.0,
          high: 155.0,
          low: 149.0,
          close: 152.0,
          volume: 1000
        )
      end

      missing_dates = subject.send(:find_missing_dates, 'AAPL')
      expect(missing_dates).to be_empty
    end
  end
end
