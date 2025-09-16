# frozen_string_literal: true

require 'gl_command'

# FetchAndCacheHistory Command
#
# This command handles fetching historical market data from the Alpaca API
# and intelligently caching it in the historical_bars table.
# It checks for missing data points and only fetches what's needed.
class FetchAndCacheHistory < GLCommand::Callable
  # Input parameters
  attr_reader :symbols, :start_date, :end_date

  # Output data
  attr_reader :fetched_bars, :cached_bars_count, :errors

  def initialize(symbols:, start_date:, end_date:)
    @symbols = Array(symbols).map(&:upcase)
    @start_date = parse_date(start_date)
    @end_date = parse_date(end_date)
    @fetched_bars = []
    @cached_bars_count = 0
    @errors = []
  end

  def call
    validate_inputs
    return self if context.failure?

    @symbols.each do |symbol|
      fetch_missing_data_for_symbol(symbol)
    end

    self
  rescue StandardError => e
    context.fail!(error_message: "Unexpected error: #{e.message}", exception: e)
    self
  end

  private

  def validate_inputs
    validate_symbols
    validate_dates
  end

  def validate_symbols
    if @symbols.empty?
      context.fail!(error_message: 'At least one symbol must be provided')
      return
    end

    invalid_symbols = @symbols.reject { |symbol| valid_symbol?(symbol) }
    return if invalid_symbols.empty?

    context.fail!(error_message: "Invalid symbols: #{invalid_symbols.join(', ')}")
  end

  def validate_dates
    if @start_date > @end_date
      context.fail!(error_message: 'Start date must be before or equal to end date')
      return
    end

    return unless @end_date > Date.current

    context.fail!(error_message: 'End date cannot be in the future')
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
  rescue ArgumentError => e
    context.fail!(error_message: "Date parsing error: #{e.message}")
    Date.current
  end

  def fetch_missing_data_for_symbol(symbol)
    missing_dates = find_missing_dates(symbol)
    return if missing_dates.empty?

    Rails.logger.info("Fetching #{missing_dates.size} missing data points for #{symbol}")

    # Group consecutive dates into ranges for efficient API calls
    date_ranges = group_consecutive_dates(missing_dates)

    date_ranges.each do |range_start, range_end|
      fetch_and_store_data(symbol, range_start, range_end)
    end
  rescue StandardError => e
    @errors << "Error fetching data for #{symbol}: #{e.message}"
    Rails.logger.error("Failed to fetch data for #{symbol}: #{e.message}")
  end

  def find_missing_dates(symbol)
    # Get all trading days in the date range (excluding weekends)
    all_trading_days = (@start_date..@end_date).reject do |date|
      # Monday = 1, Sunday = 0, so exclude Saturday (6) and Sunday (0)
      [0, 6].include?(date.wday)
    end

    # Get existing data from database
    existing_dates = HistoricalBar
                     .for_symbol(symbol)
                     .between_dates(@start_date.beginning_of_day, @end_date.end_of_day)
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

  def fetch_and_store_data(symbol, start_date, end_date)
    bars_data = alpaca_client.fetch_bars(symbol, start_date, end_date)

    if bars_data.empty?
      Rails.logger.warn("No data returned from Alpaca for #{symbol} between #{start_date} and #{end_date}")
      return
    end

    stored_count = store_bars(symbol, bars_data)
    @cached_bars_count += stored_count
    @fetched_bars.concat(bars_data)

    Rails.logger.info("Stored #{stored_count} bars for #{symbol}")
  rescue StandardError => e
    error_msg = "API call failed for #{symbol} (#{start_date} to #{end_date}): #{e.message}"
    @errors << error_msg
    Rails.logger.error(error_msg)
    raise e
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
