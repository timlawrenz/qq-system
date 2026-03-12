# frozen_string_literal: true

require 'faraday'
require 'json'

# SenateLdaClient
#
# Fetches corporate lobbying disclosure filings from the Senate Lobbying
# Disclosure Act (LDA) public API — free, no API key required for basic use.
#
# API docs: https://lda.senate.gov/api/v1/
# Data source: Lobbying Disclosure Act filings (LD2 quarterly reports)
#
# Replaces QuiverClient#fetch_lobbying_data and #fetch_live_lobbying. Returns
# the same hash shape so FetchLobbyingData requires no downstream changes.
#
# Ticker resolution: The LDA database stores company (client) names, not
# tickers. This client resolves ticker → company_name via CompanyProfile.
# Tickers without a cached profile are skipped with a warning.
#
# Rate limits: anonymous access allows ~100 req/min. The optional env var
# SENATE_LDA_API_KEY (free registration at lda.senate.gov) raises limits.
#
# Period mapping: LDA uses "H1"/"H2" (semi-annual) or "Q1"–"Q4" (quarterly).
# We normalise all periods to the format "Q? YYYY" or "H? YYYY".
class SenateLdaClient
  BASE_URL         = 'https://lda.senate.gov'
  FILINGS_ENDPOINT = '/api/v1/filings/'
  LD2_FILING_TYPE  = 'LD2'
  REQUEST_INTERVAL = 0.7  # ~85 req/min, safely below 100 req/min
  PAGE_SIZE        = 25   # LDA API max page size
  MAX_PAGES        = 4    # cap per ticker

  def initialize
    @api_key    = ENV.fetch('SENATE_LDA_API_KEY', nil)
    @connection = build_connection
    @last_request_at = nil
    @api_calls = []
  end

  attr_reader :api_calls

  # Fetch lobbying records for a single ticker.
  # Resolves ticker → company name via CompanyProfile, then searches the LDA API.
  #
  # @param ticker [String]
  # @param start_date [Date] earliest filing date to include
  # @param end_date   [Date] latest filing date to include
  # @param limit      [Integer] maximum records to return
  # @return [Array<Hash>] normalised lobbying records
  def fetch_lobbying_data(ticker, start_date: 1.year.ago.to_date, end_date: Date.current, limit: 200)
    company_name = resolve_company_name(ticker)
    unless company_name
      Rails.logger.warn("[SenateLdaClient] No company profile for #{ticker} — skipping")
      return []
    end

    fetch_paginated(ticker: ticker, company_name: company_name,
                    start_date: start_date, end_date: end_date, limit: limit)
  end

  private

  def resolve_company_name(ticker)
    CompanyProfile.find_by(ticker: ticker.to_s.upcase)&.company_name
  end

  def fetch_paginated(ticker:, company_name:, start_date:, end_date:, limit:)
    records = []
    page    = 1

    loop do
      params = build_params(company_name, start_date, end_date, page)
      body   = get_request(FILINGS_ENDPOINT, params)
      filings = body&.dig('results') || []

      records.concat(normalize_filings(filings, ticker))

      break if filings.size < PAGE_SIZE
      break if records.size >= limit
      break if page >= MAX_PAGES
      break unless body&.dig('next')

      page += 1
    end

    records.first(limit)
  end

  def build_params(company_name, start_date, end_date, page)
    {
      filing_type: LD2_FILING_TYPE,
      client_name: company_name,
      filing_dt_posted_after: start_date.to_s,
      filing_dt_posted_before: end_date.to_s,
      page: page,
      page_size: PAGE_SIZE
    }
  end

  def normalize_filings(filings, ticker)
    filings.filter_map do |filing|
      filing_date = parse_date(filing['filing_dt_posted'] || filing['dt_posted'])
      next if filing_date.nil?

      amount = parse_amount(filing['income']) || parse_amount(filing['expenses']) || BigDecimal('0')
      registrant_name = filing.dig('registrant', 'name') || filing.dig('registrant', 'registrant_name')
      client_name     = filing.dig('client', 'client_name') || filing.dig('client', 'name')

      activities = Array(filing['lobbying_activities'])
      issue          = extract_issues(activities)
      specific_issue = extract_specific_issues(activities)

      {
        ticker: ticker,
        date: filing_date,
        quarter: normalise_period(filing['period_code'], filing['period_year'], filing_date),
        amount: amount,
        client: client_name,
        registrant: registrant_name,
        issue: issue,
        specific_issue: specific_issue
      }
    rescue StandardError => e
      Rails.logger.error("[SenateLdaClient] Failed to parse filing: #{e.message}")
      nil
    end
  end

  def extract_issues(activities)
    codes = activities.filter_map { |a| a['general_issue_code'] }.uniq
    codes.join(', ').presence
  end

  def extract_specific_issues(activities)
    descriptions = activities.filter_map { |a| a['description']&.strip }.uniq
    descriptions.first(3).join(' | ').presence
  end

  # Maps LDA period codes to "Q? YYYY" / "H? YYYY" strings, falling back to
  # deriving the quarter from the filing date.
  def normalise_period(period_code, period_year, filing_date)
    if period_code.present? && period_year.present?
      code = period_code.to_s.upcase
      return "#{code} #{period_year}" if code.match?(/\A[HQ][1-4]\z/)
    end

    quarter_from_date(filing_date)
  end

  def quarter_from_date(date)
    return nil if date.nil?

    qtr = ((date.month - 1) / 3) + 1
    "Q#{qtr} #{date.year}"
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_amount(value)
    return nil if value.nil?

    BigDecimal(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def get_request(endpoint, params)
    rate_limit

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response   = @connection.get(endpoint, params)
    duration   = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    record_api_call(endpoint, response, duration)
    return nil unless response.status == 200

    JSON.parse(response.body)
  rescue Faraday::Error, JSON::ParserError => e
    Rails.logger.error("[SenateLdaClient] Request to #{endpoint} failed: #{e.message}")
    nil
  end

  def record_api_call(endpoint, response, duration_ms)
    @api_calls << {
      endpoint: endpoint,
      status_code: response.status,
      duration_ms: duration_ms,
      timestamp: Time.current,
      request: { method: 'GET', endpoint: endpoint },
      response: { status_code: response.status, body: response.body&.truncate(500) }
    }
  end

  def rate_limit
    return unless @last_request_at

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request_at
    sleep(REQUEST_INTERVAL - elapsed) if elapsed < REQUEST_INTERVAL
  ensure
    @last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def build_connection
    Faraday.new(url: BASE_URL) do |conn|
      conn.headers['Accept']     = 'application/json'
      conn.headers['User-Agent'] = 'qq-system/1.0 (lobbying-research)'
      conn.headers['Authorization'] = "Token #{@api_key}" if @api_key.present?
      conn.options.timeout      = 30
      conn.options.open_timeout = 10
    end
  end
end
