# frozen_string_literal: true

# FetchAndCacheHistory Command
#
# This command handles fetching historical market data from the Alpaca API
# and intelligently caching it in the historical_bars table.
# It checks for missing data points and only fetches what's needed.
class FetchAndCacheHistory < GLCommand::Callable
  requires :symbols, :start_date, :end_date
  returns :fetched_bars, :cached_bars_count, :api_errors

  validates :symbols, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :validate_symbol_format
  validate :validate_date_range

  def call
    symbols = Array(context.symbols).map(&:upcase)
    start_date = parse_date(context.start_date)
    end_date = parse_date(context.end_date)

    fetched_bars = []
    cached_bars_count = 0
    api_errors = []

    symbols.each do |symbol|
      missing_dates = find_missing_dates(symbol, start_date, end_date)
      next if missing_dates.empty?

      Rails.logger.info("Fetching #{missing_dates.size} missing data points for #{symbol}")

      # Group consecutive dates into ranges for efficient API calls
      date_ranges = group_consecutive_dates(missing_dates)

      date_ranges.each do |range_start, range_end|
        bars_data = alpaca_client.fetch_bars(symbol, range_start, range_end)

        if bars_data.empty?
          Rails.logger.warn("No data returned from Alpaca for #{symbol} between #{range_start} and #{range_end}")
          next
        end

        stored_count = store_bars(symbol, bars_data)
        cached_bars_count += stored_count
        fetched_bars.concat(bars_data)

        Rails.logger.info("Stored #{stored_count} bars for #{symbol}")
      rescue StandardError => e
        error_msg = "API call failed for #{symbol} (#{range_start} to #{range_end}): #{e.message}"
        api_errors << error_msg
        Rails.logger.error(error_msg)
      end
    rescue StandardError => e
      api_errors << "Error fetching data for #{symbol}: #{e.message}"
      Rails.logger.error("Failed to fetch data for #{symbol}: #{e.message}")
    end

    # Assign results to context
    context.fetched_bars = fetched_bars
    context.cached_bars_count = cached_bars_count
    context.api_errors = api_errors
  rescue StandardError => e
    stop_and_fail!("Unexpected error: #{e.message}")
  end

  private

  def validate_symbol_format
    symbols = Array(context.symbols)
    return if symbols.all? { |symbol| valid_symbol?(symbol.to_s.upcase) }

    invalid_symbols = symbols.reject { |symbol| valid_symbol?(symbol.to_s.upcase) }
    errors.add(:symbols, "Invalid symbols: #{invalid_symbols.join(', ')}")
  end

  def validate_date_range
    start_date = parse_date(context.start_date)
    end_date = parse_date(context.end_date)

    errors.add(:end_date, 'End date must be after or equal to start date') if start_date > end_date

    errors.add(:end_date, 'End date cannot be in the future') if end_date > Date.current
  rescue StandardError => e
    errors.add(:base, "Date parsing error: #{e.message}")
  end

  def valid_symbol?(symbol)
    symbol.is_a?(String) && symbol.match?(/\A[A-Z]{1,5}\z/)
  end

  def parse_date(date)
    case date
    when Date
      date
    when String
      Date.parse(date)
    when Time
      date.to_date
    else
      raise ArgumentError, "Invalid date format: #{date}"
    end
  end

  def find_missing_dates(symbol, start_date, end_date)
    # Get all trading days in the date range (excluding weekends)
    weekend_days = [0, 6] # Saturday and Sunday
    all_trading_days = (start_date..end_date).reject do |date|
      weekend_days.include?(date.wday)
    end

    # Get existing data from database
    existing_dates = HistoricalBar
                     .for_symbol(symbol)
                     .between_dates(start_date.beginning_of_day, end_date.end_of_day)
                     .pluck(:timestamp)
                     .to_set(&:to_date)

    # Return missing dates
    all_trading_days.reject { |date| existing_dates.include?(date) }
  end

  def group_consecutive_dates(dates)
    return [] if dates.empty?

    sorted_dates = dates.sort
    ranges = []
    current_start = sorted_dates.first
    current_end = sorted_dates.first

    sorted_dates.each_cons(2) do |current, next_date|
      if next_date == current + 1.day
        current_end = next_date
      else
        ranges << [current_start, current_end]
        current_start = next_date
        current_end = next_date
      end
    end

    # Add the last range
    ranges << [current_start, current_end]
    ranges
  end

  def store_bars(symbol, bars_data)
    stored_count = 0

    bars_data.each do |bar_data|
      HistoricalBar.create!(
        symbol: symbol,
        timestamp: bar_data[:timestamp],
        open: bar_data[:open],
        high: bar_data[:high],
        low: bar_data[:low],
        close: bar_data[:close],
        volume: bar_data[:volume]
      )
      stored_count += 1
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("Failed to store bar for #{symbol}: #{e.message}")
    rescue ActiveRecord::RecordNotUnique
      # Data already exists, skip silently
      Rails.logger.debug { "Bar already exists for #{symbol} at #{bar_data[:timestamp]}" }
    end

    stored_count
  end

  def alpaca_client
    @alpaca_client ||= AlpacaApiClient.new
  end
end
