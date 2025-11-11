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
    context.symbols = Array(context.symbols).map(&:upcase)
    context.fetched_bars = []
    context.api_errors = []

    fetch_for_symbols
  rescue StandardError => e
    stop_and_fail!("Unexpected error: #{e.message}")
  end

  private

  def fetch_for_symbols
    missing_dates_by_symbol = find_missing_dates_for_symbols(symbols, start_date, end_date)
    return if missing_dates_by_symbol.empty?

    requests = group_symbols_by_date_ranges(missing_dates_by_symbol)

    requests.each do |date_range, syms|
      fetch_result = FetchAlpacaData.call!(
        symbols: syms,
        start_date: date_range.min,
        end_date: date_range.max
      )
      process_fetch_result(fetch_result) if fetch_result.success?
    end
  end

  def group_symbols_by_date_ranges(missing_dates_by_symbol)
    # Invert the hash to group symbols by missing dates
    dates_by_symbol = {}
    missing_dates_by_symbol.each do |symbol, dates|
      group_continuous_dates(dates).each do |date_range|
        dates_by_symbol[date_range] ||= []
        dates_by_symbol[date_range] << symbol
      end
    end
    dates_by_symbol
  end

  def find_missing_dates_for_symbols(symbols, start_date, end_date)
    all_trading_days = trading_days(start_date, end_date)
    existing_dates_by_symbol = find_existing_dates(symbols, start_date, end_date)

    symbols.each_with_object({}) do |symbol, missing|
      existing_dates = existing_dates_by_symbol[symbol] || Set.new
      missing_dates = all_trading_days.reject { |date| existing_dates.include?(date) }
      missing[symbol] = missing_dates if missing_dates.present?
    end
  end

  def find_existing_dates(symbols, start_date, end_date)
    HistoricalBar
      .for_symbol(symbols)
      .between_dates(start_date.beginning_of_day, end_date.end_of_day)
      .pluck(:symbol, :timestamp)
      .group_by(&:first)
      .transform_values { |v| v.map(&:second).to_set(&:to_date) }
  end

  def trading_days(start_date, end_date)
    weekend_days = [0, 6] # Saturday and Sunday
    (start_date..end_date).reject do |date|
      weekend_days.include?(date.wday)
    end
  end

  def group_continuous_dates(dates)
    dates.sort.slice_when { |prev, curr| curr != prev.next_day }.map { |group| (group.first..group.last) }
  end

  def process_fetch_result(fetch_result)
    bars_data = fetch_result.bars_data
    api_errors.concat(fetch_result.api_errors)

    return if bars_data.empty?

    store_bars(bars_data)
    fetched_bars.concat(bars_data)
  end

  def validate_date_range
    errors.add(:end_date, 'End date must be after or equal to start date') if start_date > end_date
    errors.add(:end_date, 'End date cannot be in the future') if end_date > Date.current
  rescue StandardError => e
    errors.add(:base, "Date parsing error: #{e.message}")
  end

  def store_bars(bars_data)
    return unless bars_data.is_a?(Array)

    bars_data.each do |bar_data|
      HistoricalBar.create!(
        symbol: bar_data[:symbol],
        timestamp: bar_data[:timestamp],
        open: bar_data[:open],
        high: bar_data[:high],
        low: bar_data[:low],
        close: bar_data[:close],
        volume: bar_data[:volume]
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Failed to store bar for #{bar_data[:symbol]}: #{e.record.errors.full_messages.join(', ')}")
    rescue ActiveRecord::RecordNotUnique
      # Data already exists, skip silently
      Rails.logger.debug { "Bar already exists for #{bar_data[:symbol]} at #{bar_data[:timestamp]}" }
    end
  end
end
