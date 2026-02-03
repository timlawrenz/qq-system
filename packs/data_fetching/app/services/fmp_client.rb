# frozen_string_literal: true

require 'faraday'
require 'json'

# FmpClient
#
# Minimal client for Financial Modeling Prep (FMP) "stable" endpoints.
class FmpClient
  BASE_URL = 'https://financialmodelingprep.com'

  REQUEST_INTERVAL = 0.1

  def initialize
    @api_key = api_key
    @connection = build_connection
    @last_request_at = nil
  end

  # @return [Hash, nil]
  def fetch_company_profile(ticker)
    raise ArgumentError, 'ticker is required' if ticker.blank?

    rate_limit

    response = @connection.get('/stable/profile', { symbol: ticker.to_s.upcase, apikey: @api_key })

    handle_response(response) do |payload|
      row = Array(payload).first
      return nil unless row.is_a?(Hash)

      {
        ticker: row['symbol'] || row['Symbol'] || ticker.to_s.upcase,
        company_name: row['companyName'] || row['CompanyName'] || row['name'],
        sector: row['sector'] || row['Sector'],
        industry: row['industry'] || row['Industry'],
        cik: row['cik'] || row['CIK'],
        cusip: row['cusip'] || row['CUSIP'],
        isin: row['isin'] || row['ISIN'],
        annual_revenue: row['revenue'] || row['Revenue'] # may be nil depending on plan/payload
      }
    end
  end

  private

  def api_key
    ENV.fetch('FMP_API_KEY', nil) || Rails.application.credentials.dig(:financial_modeling_prep, :api_key)
  end

  def build_connection
    raise StandardError, 'Missing required FMP_API_KEY' if @api_key.blank? && !Rails.env.local?

    if @api_key.blank? && Rails.env.local?
      Rails.logger.warn('[FmpClient] Missing FMP_API_KEY; returning empty profiles in local/test')
      @api_key = 'test-fmp-key'
    end

    Faraday.new(url: BASE_URL) do |conn|
      conn.headers['Accept'] = 'application/json'
      conn.options.timeout = 10
      conn.options.open_timeout = 5
    end
  end

  def rate_limit
    return if @last_request_at.nil?

    elapsed = Time.current - @last_request_at
    sleep(REQUEST_INTERVAL - elapsed) if elapsed < REQUEST_INTERVAL
  ensure
    @last_request_at = Time.current
  end

  def handle_response(response)
    body = JSON.parse(response.body.to_s)

    case response.status
    when 200
      yield(body)
    when 401
      raise StandardError, 'FMP authentication failed. Check FMP_API_KEY.'
    when 403
      raise StandardError, 'FMP access forbidden. Check plan permissions.'
    when 429
      raise StandardError, 'FMP rate limit exceeded. Retry later.'
    else
      msg = body.is_a?(Hash) ? (body['error'] || body['message'] || body.to_s) : body.to_s
      raise StandardError, "FMP error (#{response.status}): #{msg}"
    end
  rescue JSON::ParserError => e
    raise StandardError, "Failed to parse FMP response: #{e.message}"
  end
end
