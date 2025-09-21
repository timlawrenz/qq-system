# frozen_string_literal: true

require 'faraday'

# QuiverClient
#
# Service for interacting with the Quiver Quantitative API
# Handles authentication, rate limiting, and data formatting for congressional trades
class QuiverClient
  # API configuration
  BASE_URL = 'https://api.quiverquant.com'
  API_VERSION = 'v1'
  TIMEOUT = 30

  # Rate limiting - be conservative with external API
  MAX_REQUESTS_PER_MINUTE = 60
  REQUEST_INTERVAL = 60.0 / MAX_REQUESTS_PER_MINUTE

  def initialize
    @last_request_time = 0
    @connection = build_connection
  end

  # Fetch congressional trades from Quiver API
  # Returns array of hashes with trade data
  def fetch_congressional_trades(options = {})
    rate_limit

    path = "/#{API_VERSION}/congressional-trades"
    params = build_params(options)

    Rails.logger.info("Fetching congressional trades from Quiver API with params: #{params}")

    begin
      response = @connection.get(path, params)
      handle_response(response)
    rescue Faraday::Error => e
      handle_api_error(e)
    end
  end

  private

  def build_connection
    Faraday.new(url: BASE_URL) do |conn|
      conn.request :url_encoded
      conn.adapter Faraday.default_adapter
      conn.options.timeout = TIMEOUT
      conn.options.open_timeout = TIMEOUT

      # Add API key authentication
      conn.headers['Authorization'] = "Bearer #{api_key}"
      conn.headers['User-Agent'] = 'QuiverQuant-RubyClient/1.0'
    end
  end

  def build_params(options)
    params = {}

    # Add date filtering if provided
    params[:start_date] = options[:start_date].strftime('%Y-%m-%d') if options[:start_date]
    params[:end_date] = options[:end_date].strftime('%Y-%m-%d') if options[:end_date]

    # Add ticker filtering if provided
    params[:ticker] = options[:ticker] if options[:ticker]

    # Add limit if provided (default to reasonable limit)
    params[:limit] = options[:limit] || 100

    params
  end

  def handle_response(response)
    # Parse JSON response body manually (Faraday 1.2.0 doesn't have :json middleware)
    parsed_body = response.body.is_a?(String) ? JSON.parse(response.body) : response.body

    case response.status
    when 200
      parse_trades_response(parsed_body)
    when 401
      raise StandardError, 'Quiver API authentication failed. Check your API credentials.'
    when 403
      raise StandardError, 'Quiver API access forbidden. Check your subscription level.'
    when 422
      error_msg = parsed_body['message'] || 'Invalid request parameters'
      raise StandardError, "Quiver API validation error: #{error_msg}"
    when 429
      raise StandardError, 'Quiver API rate limit exceeded. Please retry later.'
    else
      error_msg = parsed_body['message'] || 'Unknown error'
      raise StandardError, "Quiver API error (#{response.status}): #{error_msg}"
    end
  rescue JSON::ParserError => e
    raise StandardError, "Failed to parse Quiver API response: #{e.message}"
  end

  def parse_trades_response(response_body)
    # Handle both wrapped ({"data": [...]}) and direct array responses
    trades_data = if response_body.is_a?(Hash) && response_body['data']
                    response_body['data']
                  elsif response_body.is_a?(Array)
                    response_body
                  else
                    []
                  end

    return [] unless trades_data.is_a?(Array)

    trades_data.map do |trade|
      {
        ticker: trade['ticker'],
        company: trade['company'],
        trader_name: trade['trader_name'],
        trader_source: trade['trader_source'] || 'congress',
        transaction_date: parse_date(trade['transaction_date']),
        transaction_type: trade['transaction_type'],
        trade_size_usd: trade['trade_size_usd'],
        disclosed_at: parse_datetime(trade['disclosed_at'])
      }
    end
  rescue StandardError => e
    Rails.logger.error("Failed to parse Quiver trades response: #{e.message}")
    []
  end

  def parse_date(date_string)
    return nil if date_string.blank?

    Date.parse(date_string)
  rescue ArgumentError
    Rails.logger.warn("Invalid date format in Quiver API response: #{date_string}")
    nil
  end

  def parse_datetime(datetime_string)
    return nil if datetime_string.blank?

    result = Time.zone.parse(datetime_string)

    Rails.logger.warn("Invalid datetime format in Quiver API response: #{datetime_string}") if result.nil?

    result
  end

  def handle_api_error(error)
    error_msg = case error
                when Faraday::TimeoutError
                  'Quiver API timeout'
                when Faraday::ConnectionFailed
                  'Failed to connect to Quiver API'
                else
                  "Quiver API network error: #{error.message}"
                end

    Rails.logger.error(error_msg)
    raise StandardError, error_msg
  end

  def rate_limit
    current_time = Time.current.to_f
    time_since_last_request = current_time - @last_request_time

    if time_since_last_request < REQUEST_INTERVAL
      sleep_time = REQUEST_INTERVAL - time_since_last_request
      Rails.logger.debug { "Rate limiting: sleeping for #{sleep_time.round(2)} seconds" }
      sleep(sleep_time)
    end

    @last_request_time = Time.current.to_f
  end

  def api_key
    @api_key ||= fetch_credential('QUIVER_API_KEY', 'test-api-key')
  end

  def fetch_credential(env_var, default_value)
    # Try environment variable first
    env_value = ENV.fetch(env_var, nil)
    return env_value if env_value.present?

    # Try Rails credentials second
    credentials_value = Rails.application.credentials.dig(:quiver, env_var.downcase.to_sym)
    return credentials_value if credentials_value.present?

    # Use default for development/test
    if Rails.env.local?
      Rails.logger.warn("Using default #{env_var} for #{Rails.env} environment")
      return default_value
    end

    # Fail in production without real credentials
    raise StandardError, "Missing required Quiver credential: #{env_var}"
  end
end
