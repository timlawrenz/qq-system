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
# Returns data in the same format as the former QuiverClient#fetch_congressional_trades so that
# no downstream code (FetchQuiverData command, trading strategies) requires changes.
#
# API keys: None required. Rate limits: None (static S3 files).
#
# rubocop:disable Metrics/ClassLength, Metrics/MethodLength
class HouseSenateDisclosuresClient
  HOUSE_DATA_URL   = 'https://house-stock-watcher-data.s3-us-west-2.amazonaws.com/data/all_transactions.json'
  SENATE_DATA_URL  = 'https://senate-stock-watcher-data.s3-us-west-2.amazonaws.com/aggregate/all_transactions.json'

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
  # @return [Array<Hash>] trade hashes matching the former QuiverClient output:
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

  # When true, use the kadoa-org/congress-trading-monitor open dataset for House
  # data instead of the community S3 aggregator. The S3 bucket has been returning
  # 403 since ~March 2026.
  HOUSE_KADOA_ENABLED = true

  def fetch_house_trades(start_date, end_date)
    # Try the kadoa open dataset first
    if HOUSE_KADOA_ENABLED
      begin
        trades = fetch_house_trades_from_kadoa(start_date, end_date)
        if trades.any?
          Rails.logger.info("HouseSenateDisclosuresClient: #{trades.size} House trades from kadoa")
          return trades
        end
      rescue StandardError => e
        Rails.logger.error("HouseSenateDisclosuresClient: kadoa House fetch failed — #{e.message}")
      end
    end

    # Fall back to the (now-dead) community S3 aggregator
    raw_data = download_json(HOUSE_DATA_URL, label: 'house')
    return [] unless raw_data.is_a?(Array)

    parsed = raw_data.filter_map { |r| parse_house_record(r, start_date, end_date) }
    Rails.logger.info("HouseSenateDisclosuresClient: #{parsed.size} House trades in range")
    parsed
  rescue StandardError => e
    Rails.logger.error("HouseSenateDisclosuresClient: House fetch failed — #{e.message}")
    []
  end

  def fetch_house_trades_from_kadoa(start_date, end_date)
    client = KadoaCongressClient.new
    trades = client.fetch_congressional_trades(
      start_date: start_date,
      end_date: end_date,
      chamber: 'house'
    )
    @api_calls.concat(client.api_calls) if client.api_calls
    trades
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

  # When true, use the native Senate EFD scraper instead of the community S3
  # aggregator. The S3 bucket has been returning 403 since ~March 2026.
  SENATE_EFD_ENABLED = true

  def fetch_senate_trades(start_date, end_date)
    # Try the native Senate EFD scraper first
    if SENATE_EFD_ENABLED
      begin
        trades = fetch_senate_trades_from_efd(start_date)
        if trades.any?
          Rails.logger.info("HouseSenateDisclosuresClient: #{trades.size} Senate trades from EFD")
          return trades
        end
      rescue StandardError => e
        Rails.logger.error("HouseSenateDisclosuresClient: Senate EFD fetch failed — #{e.message}")
      end
    end

    # Fall back to the (now-dead) community S3 aggregator
    raw_data = download_json(SENATE_DATA_URL, label: 'senate')
    return [] unless raw_data.is_a?(Array)

    parsed = raw_data.filter_map { |r| parse_senate_record(r, start_date, end_date) }
    Rails.logger.info("HouseSenateDisclosuresClient: #{parsed.size} Senate trades in range")
    parsed
  rescue StandardError => e
    Rails.logger.error("HouseSenateDisclosuresClient: Senate fetch failed — #{e.message}")
    []
  end

  def fetch_senate_trades_from_efd(start_date)
    # Use the most recent Senate trade's disclosed_at as the watermark
    # to avoid re-fetching PTRs we've already processed.
    watermark = latest_senate_disclosure_date
    effective_start = if watermark && watermark > start_date
                        watermark
                      else
                        start_date
                      end

    client = SenateEfd::Client.new
    trades = client.fetch_trades_since(effective_start)
    @api_calls.concat(client.api_calls) if client.api_calls
    trades
  end

  # Return the most recent disclosed_at date for Senate trades already in the DB.
  def latest_senate_disclosure_date
    QuiverTrade
      .where(trader_source: 'congress')
      .where.not(disclosed_at: nil)
      .maximum(:disclosed_at)
      &.to_date
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
