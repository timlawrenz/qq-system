# frozen_string_literal: true

require 'faraday'

# HouseSenateDisclosuresClient
#
# Fetches STOCK Act Periodic Transaction Reports (PTR) from community-maintained
# aggregators of the official House and Senate financial disclosure systems:
#
# - House: House Stock Watcher (aggregates House Clerk PTR filings)
#     Official source: https://disclosures.house.gov/FinancialDisclosure
#     Data endpoint:   https://house-stock-watcher-data.s3-us-east-2.amazonaws.com/data/all_transactions.json
#
# - Senate: Senate Stock Watcher (aggregates Senate eFTS PTR filings)
#     Official source: https://efts.senate.gov/EFTS-Public/browse
#     Data endpoint:   https://senate-stock-watcher-data.s3-us-east-2.amazonaws.com/aggregate/all_transactions.json
#
# These community datasets are updated automatically from the official government XML
# filings and include normalized ticker symbols — the same data QuiverQuant provided,
# from the same primary sources, at no cost.
#
# Returns data in the same format as QuiverClient#fetch_congressional_trades so that
# no downstream code (FetchQuiverData command, trading strategies) requires changes.
#
# API keys: None required. Rate limits: None (static S3 files).
#
# rubocop:disable Metrics/ClassLength, Metrics/MethodLength
class HouseSenateDisclosuresClient
  HOUSE_DATA_URL   = 'https://house-stock-watcher-data.s3-us-east-2.amazonaws.com/data/all_transactions.json'
  SENATE_DATA_URL  = 'https://senate-stock-watcher-data.s3-us-east-2.amazonaws.com/aggregate/all_transactions.json'

  TIMEOUT      = 120 # Large JSON files — allow adequate time
  OPEN_TIMEOUT = 20

  attr_reader :api_calls

  def initialize
    @api_calls = []
  end

  # Fetch STOCK Act congressional trades disclosed within the date range.
  #
  # @param options [Hash]
  #   :start_date [Date]    disclosure date range start (default: 60 days ago)
  #   :end_date   [Date]    disclosure date range end   (default: today)
  #   :ticker     [String]  optional: filter to a single ticker
  #   :limit      [Integer] optional: cap total records returned
  #
  # @return [Array<Hash>] trade hashes matching QuiverClient output:
  #   :ticker, :company, :trader_name, :trader_source (:congress),
  #   :transaction_date, :transaction_type, :trade_size_usd, :disclosed_at
  def fetch_congressional_trades(options = {})
    start_date = options[:start_date] || 60.days.ago.to_date
    end_date   = options[:end_date]   || Date.current
    ticker     = options[:ticker]&.to_s&.upcase
    limit      = options[:limit]

    Rails.logger.info(
      "HouseSenateDisclosuresClient: Fetching congressional trades " \
      "disclosed #{start_date}..#{end_date}#{ticker ? " ticker=#{ticker}" : ''}"
    )

    trades = []
    trades.concat(fetch_house_trades(start_date, end_date))
    trades.concat(fetch_senate_trades(start_date, end_date))

    trades.select! { |t| t[:ticker] == ticker } if ticker.present?
    trades = trades.first(limit) if limit.present?

    Rails.logger.info(
      "HouseSenateDisclosuresClient: #{trades.size} total trades in date range"
    )

    trades
  end

  private

  # ─── House of Representatives ────────────────────────────────────────────── #

  def fetch_house_trades(start_date, end_date)
    raw_data = download_json(HOUSE_DATA_URL, label: 'house')
    return [] unless raw_data.is_a?(Array)

    parsed = raw_data.filter_map { |r| parse_house_record(r, start_date, end_date) }
    Rails.logger.info("HouseSenateDisclosuresClient: #{parsed.size} House trades in range")
    parsed
  rescue StandardError => e
    Rails.logger.error("HouseSenateDisclosuresClient: House fetch failed — #{e.message}")
    []
  end

  def parse_house_record(record, start_date, end_date)
    return nil unless stock_asset?(record['asset_type'])

    disclosed_at = parse_date(record['disclosure_date'])
    return nil unless disclosed_at
    return nil unless disclosed_at >= start_date && disclosed_at <= end_date

    transaction_date = parse_date(record['transaction_date'])
    return nil if transaction_date.nil?

    ticker = record['ticker'].to_s.strip.upcase
    return nil if ticker.blank? || ticker == '--'

    transaction_type = normalize_transaction_type(record['type'])
    return nil unless transaction_type

    {
      ticker: ticker,
      company: record['asset_description']&.strip,
      trader_name: record['representative']&.strip,
      trader_source: 'congress',
      transaction_date: transaction_date,
      transaction_type: transaction_type,
      trade_size_usd: record['amount'],
      disclosed_at: disclosed_at.to_datetime
    }
  end

  # ─── Senate ──────────────────────────────────────────────────────────────── #

  def fetch_senate_trades(start_date, end_date)
    raw_data = download_json(SENATE_DATA_URL, label: 'senate')
    return [] unless raw_data.is_a?(Array)

    parsed = raw_data.filter_map { |r| parse_senate_record(r, start_date, end_date) }
    Rails.logger.info("HouseSenateDisclosuresClient: #{parsed.size} Senate trades in range")
    parsed
  rescue StandardError => e
    Rails.logger.error("HouseSenateDisclosuresClient: Senate fetch failed — #{e.message}")
    []
  end

  def parse_senate_record(record, start_date, end_date)
    return nil unless stock_asset?(record['asset_type'])

    # Senate uses "MM/DD/YYYY" for disclosure_date
    disclosed_at = parse_date(record['disclosure_date'])
    return nil unless disclosed_at
    return nil unless disclosed_at >= start_date && disclosed_at <= end_date

    # Senate uses "YYYY-MM-DDTHH:MM:SS" for transaction_date
    transaction_date = parse_date(record['transaction_date'])
    return nil if transaction_date.nil?

    ticker = record['ticker'].to_s.strip.upcase
    return nil if ticker.blank? || ticker == '--'

    transaction_type = normalize_transaction_type(record['type'])
    return nil unless transaction_type

    {
      ticker: ticker,
      company: record['asset_description']&.strip,
      trader_name: record['senator']&.strip,
      trader_source: 'congress',
      transaction_date: transaction_date,
      transaction_type: transaction_type,
      trade_size_usd: record['amount'],
      disclosed_at: disclosed_at.to_datetime
    }
  end

  # ─── Shared helpers ──────────────────────────────────────────────────────── #

  def download_json(url, label:)
    start_time = Time.current

    conn = Faraday.new do |f|
      f.options.timeout      = TIMEOUT
      f.options.open_timeout = OPEN_TIMEOUT
    end

    response = conn.get(url)
    duration = ((Time.current - start_time) * 1000).to_i

    @api_calls << {
      endpoint:     url,
      status_code:  response.status,
      duration_ms:  duration,
      timestamp:    start_time,
      request:      { method: 'GET', endpoint: url, params: {} },
      response:     { status_code: response.status, body: "[#{label} data — #{response.body.bytesize} bytes]" }
    }

    raise "HTTP #{response.status} fetching #{label} disclosures data from #{url}" unless response.status == 200

    JSON.parse(response.body)
  rescue Faraday::Error => e
    duration = ((Time.current - start_time) * 1000).to_i
    @api_calls << {
      endpoint:    url,
      status_code: 0,
      duration_ms: duration,
      timestamp:   start_time,
      request:     { method: 'GET', endpoint: url, params: {} },
      error:       e.message
    }
    raise "Connection error fetching #{label} disclosures: #{e.message}"
  end

  # Only trade stocks, not bonds, funds, options, etc.
  def stock_asset?(asset_type)
    return true if asset_type.blank? # inclusive when type is absent

    %w[Stock stock].include?(asset_type.to_s.strip)
  end

  # Normalize free-text transaction type → 'Purchase' | 'Sale' | nil
  def normalize_transaction_type(raw)
    case raw.to_s.strip.downcase
    when /purchase|buy|acqui/
      'Purchase'
    when /sale|sell|sold|dispos/
      'Sale'
    else
      nil # skip exchanges, gifts, awards, etc.
    end
  end

  # Handles: "MM/DD/YYYY", "YYYY-MM-DD", "YYYY-MM-DDTHH:MM:SS"
  def parse_date(str)
    return nil if str.blank?

    s = str.to_s.strip
    if s.include?('T')
      DateTime.parse(s).to_date
    elsif s.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z})
      Date.strptime(s, '%m/%d/%Y')
    else
      Date.parse(s)
    end
  rescue ArgumentError, TypeError, Date::Error
    nil
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength
