# frozen_string_literal: true

# FetchAlpacaData Command
#
# This command is solely responsible for loading data from the Alpaca API.
# It has no awareness of the caching layer and focuses only on data retrieval.
class FetchAlpacaData < GLCommand::Callable
  requires :symbols, :start_date, :end_date
  returns :bars_data, :api_errors

  validates :symbols, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :validate_symbol_format
  validate :validate_date_range

  def call
    symbols = Array(context.symbols).map { |s| s.to_s.upcase }
    start_date = parse_date(context.start_date)
    end_date = parse_date(context.end_date)

    api_errors = []
    bars_data = []

    # Group consecutive dates into ranges for efficient API calls
    date_ranges = group_consecutive_dates(get_trading_days(start_date, end_date))

    date_ranges.each do |range_start, range_end|
      bars_data.concat(fetch_bars_for_range(symbols, range_start, range_end))
    rescue StandardError => e
      error_msg = "API call failed for #{symbols.join(', ')} (#{range_start} to #{range_end}): #{e.message}"
      api_errors << error_msg
      Rails.logger.error(error_msg)
    end

    # Assign results to context
    context.bars_data = bars_data
    context.api_errors = api_errors
  rescue StandardError => e
    stop_and_fail!("Unexpected error: #{e.message}")
  end

  private

  def validate_symbol_format
    symbols = Array(context.symbols).map { |s| s.to_s.upcase }
    invalid_symbols = symbols.reject { |s| valid_symbol?(s) }

    return if invalid_symbols.empty?

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

  def get_trading_days(start_date, end_date)
    # Get all trading days in the date range (excluding weekends)
    weekend_days = [0, 6] # Saturday and Sunday
    (start_date..end_date).reject do |date|
      weekend_days.include?(date.wday)
    end
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

  def fetch_bars_for_range(symbols, start_date, end_date)
    raw = alpaca_client.bars(
      '1D',
      symbols,
      limit: 1000,
      start_time: start_date.to_time.utc.iso8601,
      end_time: end_date.to_time.utc.iso8601
    )

    bars_data = []

    raw.each do |symbol, bars|
      Array(bars).each do |bar|
        next if bar.nil?

        if bar.respond_to?(:t)
          timestamp = Time.zone.at(bar.t)
          open = BigDecimal(bar.o.to_s)
          high = BigDecimal(bar.h.to_s)
          low = BigDecimal(bar.l.to_s)
          close = BigDecimal(bar.c.to_s)
          volume = bar.v.to_i
        else
          timestamp = bar.respond_to?(:time) ? bar.time : bar.timestamp
          open = BigDecimal(bar.open.to_s)
          high = BigDecimal(bar.high.to_s)
          low = BigDecimal(bar.low.to_s)
          close = BigDecimal(bar.close.to_s)
          volume = bar.volume.to_i
        end

        bars_data << {
          symbol: symbol,
          timestamp: timestamp,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume
        }
      end
    end

    if bars_data.empty?
      Rails.logger.warn("No data returned from Alpaca for #{symbols.join(', ')} between #{start_date} and #{end_date}")
    else
      Rails.logger.info("Fetched #{bars_data.size} bars for #{symbols.join(', ')} from #{start_date} to #{end_date}")
    end

    bars_data
  end

  def alpaca_client
    @alpaca_client ||= Alpaca::Trade::Api::Client.new
  end
end
