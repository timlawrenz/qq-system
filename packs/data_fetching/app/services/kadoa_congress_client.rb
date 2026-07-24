# frozen_string_literal: true

require 'faraday'

# KadoaCongressClient
#
# Fetches congressional stock trade data from the kadoa-org/congress-trading-monitor
# open-source project (MIT licensed). This project aggregates three official sources
# — House Clerk, Senate eFD, and OGE Executive Branch — into a single static JSON
# file served directly from GitHub raw content.
#
# Data endpoint:
#   https://raw.githubusercontent.com/kadoa-org/congress-trading-monitor/main/public/data/trades.json
#
# The file is ~4.5 MB and contains 54k+ transactions from 2012 to present.
# Updated regularly — no API key required, no rate limits (static file).
#
# Returns data in the same format as HouseSenateDisclosuresClient so that
# no downstream code requires changes.
#
# Usage
#   client = KadoaCongressClient.new
#   trades = client.fetch_congressional_trades(start_date: 45.days.ago.to_date)
class KadoaCongressClient
  DATA_URL = 'https://raw.githubusercontent.com/kadoa-org/congress-trading-monitor/main/public/data/trades.json'

  TIMEOUT      = 120 # 4.5 MB JSON file — allow adequate time
  OPEN_TIMEOUT = 20

  attr_reader :api_calls

  def initialize
    @api_calls = []
  end

  # Fetch House trades disclosed within the date range.
  #
  # @param options [Hash]
  #   :start_date [Date]  filing date range start (default: 60 days ago)
  #   :end_date   [Date]  filing date range end (default: today)
  #   :chamber    [String] filter by chamber: 'house', 'senate', or nil for all
  #   :ticker     [String] optional: filter to a single ticker
  #   :limit      [Integer] optional: cap total records returned
  #
  # @return [Array<Hash>] trade hashes:
  #   :ticker, :company, :trader_name, :trader_source (:congress),
  #   :transaction_date, :transaction_type, :trade_size_usd, :disclosed_at
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def fetch_congressional_trades(options = {})
    start_date = options[:start_date] || 60.days.ago.to_date
    end_date   = options[:end_date]   || Date.current
    chamber    = options[:chamber] || 'house'
    ticker     = options[:ticker]&.to_s&.upcase
    limit      = options[:limit]

    Rails.logger.info(
      "[KadoaCongressClient] Fetching #{chamber} trades " \
      "disclosed #{start_date}..#{end_date}#{" ticker=#{ticker}" if ticker}"
    )

    raw_data = download_json
    return [] if raw_data.empty?

    trades = raw_data.filter_map { |r| parse_record(r, start_date, end_date, chamber) }
    trades.select! { |t| t[:ticker] == ticker } if ticker.present?
    trades = trades.first(limit) if limit.present?

    Rails.logger.info(
      "[KadoaCongressClient] #{trades.size} #{chamber} trades in date range"
    )

    trades
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  rescue StandardError => e
    Rails.logger.error("[KadoaCongressClient] Fetch failed: #{e.message}")
    []
  end

  private

  def download_json
    start_time = Time.current

    conn = Faraday.new do |f|
      f.options.timeout      = TIMEOUT
      f.options.open_timeout = OPEN_TIMEOUT
    end

    response = conn.get(DATA_URL)
    record_api_call(start_time, response.status)

    raise "HTTP #{response.status} fetching kadoa data" unless response.status == 200

    JSON.parse(response.body)
  rescue Faraday::Error => e
    record_api_error(start_time, e)
    Rails.logger.error("[KadoaCongressClient] Connection error: #{e.message}")
    []
  rescue JSON::ParserError => e
    Rails.logger.error("[KadoaCongressClient] JSON parse error: #{e.message}")
    []
  end

  def record_api_call(start_time, status)
    duration = ((Time.current - start_time) * 1000).to_i
    @api_calls << {
      endpoint: DATA_URL,
      status_code: status,
      duration_ms: duration,
      timestamp: start_time
    }
  end

  def record_api_error(start_time, error)
    duration = ((Time.current - start_time) * 1000).to_i
    @api_calls << {
      endpoint: DATA_URL,
      status_code: 0,
      duration_ms: duration,
      timestamp: start_time,
      error: error.message
    }
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def parse_record(record, start_date, end_date, chamber)
    # Only include records from the requested chamber
    return nil unless record['chamber'] == chamber

    # Only stock assets (ST = Stock)
    return nil unless record['asset_type'] == 'ST'

    # Parse dates
    filing_date = parse_date(record['filing_date'])
    return nil unless filing_date
    return nil unless filing_date.between?(start_date, end_date)

    transaction_date = parse_date(record['transaction_date'])
    return nil if transaction_date.nil?

    # Ticker validation
    ticker = record['ticker'].to_s.strip.upcase
    return nil if ticker.blank? || ticker == '--'

    # Transaction type — already normalized by kadoa
    transaction_type = normalize_transaction_type(record['transaction_type'])
    return nil unless transaction_type

    {
      ticker: ticker,
      company: record['asset_name']&.strip,
      trader_name: record['filer_name']&.strip,
      trader_source: 'congress',
      transaction_date: transaction_date,
      transaction_type: transaction_type,
      trade_size_usd: record['amount_range_label'],
      disclosed_at: filing_date.to_datetime
    }
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # Kadoa normalizes types already, but double-check
  def normalize_transaction_type(raw)
    case raw.to_s.strip.downcase
    when 'purchase' then 'Purchase'
    when 'sale', 'sale (full)', 'sale (partial)' then 'Sale'
    end
  end

  def parse_date(str)
    return nil if str.blank?

    Date.parse(str.to_s.strip)
  rescue Date::Error
    nil
  end
end
