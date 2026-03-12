# frozen_string_literal: true

require 'faraday'
require 'json'

# UsaSpendingClient
#
# Fetches federal contract award data from USASpending.gov — a free,
# no-auth-required public API maintained by the US Treasury.
#
# API docs: https://api.usaspending.gov/docs/endpoints
#
# Replaces QuiverClient#fetch_government_contracts. Returns the same
# hash shape so FetchGovernmentContracts requires no changes beyond the
# client class name.
#
# Rate limits: USASpending asks for ≤60 req/min per IP (no hard limit).
# We use REQUEST_INTERVAL = 0.2s (5 req/sec), well within bounds.
#
# Ticker resolution: USASpending stores recipient names, not tickers.
# This client resolves ticker → company_name via CompanyProfile. If no
# profile is cached, the ticker is skipped and a warning is logged.
class UsaSpendingClient
  BASE_URL                = 'https://api.usaspending.gov'
  AWARDS_ENDPOINT         = '/api/v2/search/spending_by_award/'
  CONTRACT_TYPE_CODES     = %w[A B C D].freeze
  REQUEST_INTERVAL        = 0.2 # seconds between requests
  MAX_PAGES               = 5   # cap per ticker to bound execution time

  AWARD_FIELDS = [
    'Award ID',
    'Recipient Name',
    'Award Amount',
    'Start Date',
    'Awarding Agency Name',
    'Description',
    'Contract Award Type'
  ].freeze

  def initialize
    @connection = build_connection
    @last_request_at = nil
    @api_calls = []
  end

  attr_reader :api_calls

  # Returns an array of contract hashes in the same format as QuiverClient.
  # Requires +ticker+ — USASpending does not expose ticker symbols, so we
  # resolve company name from CompanyProfile first.
  def fetch_government_contracts(ticker:, start_date:, end_date:, limit: 100)
    company_name = resolve_company_name(ticker)
    unless company_name
      Rails.logger.warn("[UsaSpendingClient] No company profile for #{ticker} — skipping")
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
    contracts = []
    per_page  = [limit, 100].min
    page      = 1

    loop do
      payload  = build_payload(company_name, start_date, end_date, per_page, page)
      body     = post_request(AWARDS_ENDPOINT, payload)
      results  = body&.dig('results') || []

      contracts.concat(normalize_results(results, ticker))

      break if results.size < per_page
      break if contracts.size >= limit
      break if page >= MAX_PAGES

      page += 1
    end

    contracts.first(limit)
  end

  def build_payload(company_name, start_date, end_date, limit, page)
    {
      filters: {
        time_period: [{ start_date: start_date.to_s, end_date: end_date.to_s }],
        award_type_codes: CONTRACT_TYPE_CODES,
        recipient_search_text: [company_name]
      },
      fields: AWARD_FIELDS,
      page: page,
      limit: limit,
      sort: 'Award Amount',
      order: 'desc'
    }
  end

  def normalize_results(results, ticker)
    results.filter_map do |row|
      award_id = row['Award ID']
      amount   = row['Award Amount']

      next if award_id.blank? || amount.nil?

      contract_value = BigDecimal(amount.to_s)
      next if contract_value <= 0

      award_date = parse_date(row['Start Date'])
      next if award_date.nil?

      {
        contract_id: award_id.to_s,
        ticker: ticker,
        company: row['Recipient Name'],
        contract_value: contract_value,
        award_date: award_date,
        agency: row['Awarding Agency Name'],
        contract_type: row['Contract Award Type'],
        description: row['Description'],
        disclosed_at: nil
      }
    rescue StandardError => e
      Rails.logger.error("[UsaSpendingClient] Failed to parse award row: #{e.message}")
      nil
    end
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def post_request(endpoint, payload)
    rate_limit

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response   = @connection.post(endpoint, payload.to_json)
    duration   = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    record_api_call(endpoint, response, duration)
    return nil unless response.status == 200

    JSON.parse(response.body)
  rescue Faraday::Error, JSON::ParserError => e
    Rails.logger.error("[UsaSpendingClient] Request to #{endpoint} failed: #{e.message}")
    nil
  end

  def record_api_call(endpoint, response, duration_ms)
    @api_calls << {
      endpoint: endpoint,
      status_code: response.status,
      duration_ms: duration_ms,
      timestamp: Time.current,
      request: { method: 'POST', endpoint: endpoint },
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
      conn.headers['Content-Type'] = 'application/json'
      conn.headers['Accept']       = 'application/json'
      conn.headers['User-Agent']   = 'qq-system/1.0 (government-contracts-research)'
      conn.options.timeout         = 30
      conn.options.open_timeout    = 10
    end
  end
end
