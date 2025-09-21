# frozen_string_literal: true

# Fetch Command
#
# This command handles fetching historical market data and intelligently
# caching it in the historical_bars table. It identifies missing data points
# and delegates the actual API calls to FetchAlpacaData command.
class Fetch < GLCommand::Callable
  requires :symbols,
           start_date: Date,
           end_date: Date
  returns :fetched_bars, :api_errors

  validate :validate_date_range

  def call
    symbols.map!(&:upcase)

    context.fetched_bars = []
    context.api_errors = []

    symbols.each do |symbol|
      fetch_for_symbol(symbol)
    end
  rescue StandardError => e
    stop_and_fail!("Unexpected error: #{e.message}")
  end

  private

  def fetch_for_symbol(symbol)
    missing_dates = find_missing_dates(symbol, start_date, end_date)
    return if missing_dates.empty?

    fetch_result = FetchAlpacaData.call!(symbol: symbol, start_date: missing_dates.min, end_date: missing_dates.max)

    process_fetch_result(symbol, fetch_result) if fetch_result.success?
  rescue StandardError => e
    api_errors << "Error fetching data for #{symbol}: #{e.message}"
    Rails.logger.error("Failed to fetch data for #{symbol}: #{e.message}")
  end

  def process_fetch_result(symbol, fetch_result)
    bars_data = fetch_result.bars_data
    api_errors.concat(fetch_result.api_errors)

    return if bars_data.empty?

    store_bars(symbol, bars_data)
    fetched_bars.concat(bars_data)
  end

  def validate_date_range
    errors.add(:end_date, 'End date must be after or equal to start date') if start_date > end_date
    errors.add(:end_date, 'End date cannot be in the future') if end_date > Date.current
  rescue StandardError => e
    errors.add(:base, "Date parsing error: #{e.message}")
  end

  def valid_symbol?(symbol)
    symbol.is_a?(String) && symbol.match?(/\A[A-Z]{1,5}\z/)
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

  def store_bars(symbol, bars_data)
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
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("Failed to store bar for #{symbol}: #{e.message}")
    rescue ActiveRecord::RecordNotUnique
      # Data already exists, skip silently
      Rails.logger.debug { "Bar already exists for #{symbol} at #{bar_data[:timestamp]}" }
    end
  end
end
