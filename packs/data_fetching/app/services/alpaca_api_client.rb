# frozen_string_literal: true

# AlpacaApiClient
#
# Service for interacting with the Alpaca Market Data API
# Handles authentication, rate limiting, and data formatting
class AlpacaApiClient
  # API configuration
  BASE_URL = 'https://data.alpaca.markets'
  API_VERSION = 'v2'
  TIMEOUT = 30

  # Rate limiting (Alpaca allows 200 requests per minute for free tier)
  MAX_REQUESTS_PER_MINUTE = 180
  REQUEST_INTERVAL = 60.0 / MAX_REQUESTS_PER_MINUTE

  def initialize
    @last_request_time = 0
    @connection = build_connection
  end

  # Fetch historical bars for a symbol within a date range
  # Returns array of hashes with bar data
  def fetch_bars(symbol, start_date, end_date)
    rate_limit

    path = "/#{API_VERSION}/stocks/#{symbol}/bars"
    params = {
      start: start_date.strftime('%Y-%m-%d'),
      end: end_date.strftime('%Y-%m-%d'),
      timeframe: '1Day',
      adjustment: 'raw',
      feed: 'iex' # Use IEX feed for free tier
    }

    Rails.logger.info("Fetching bars for #{symbol} from #{start_date} to #{end_date}")

    response = @connection.get(path, params)
    handle_response(response, symbol)
  rescue Faraday::Error => e
    handle_api_error(e, symbol)
  end

  private

  def build_connection # rubocop:disable Metrics/MethodLength
    Faraday.new(
      url: BASE_URL,
      headers: {
        'APCA-API-KEY-ID' => api_key,
        'APCA-API-SECRET-KEY' => secret_key,
        'Content-Type' => 'application/json'
      }
    ) do |f|
      f.request :json
      f.response :json
      f.adapter :net_http
      f.options.timeout = TIMEOUT
      f.options.open_timeout = 10
    end
  end

  def handle_response(response, symbol) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
    case response.status
    when 200
      parse_bars_response(response.body, symbol)
    when 401
      raise StandardError, 'Alpaca API authentication failed. Check your API credentials.'
    when 403
      raise StandardError, 'Alpaca API access forbidden. Check your subscription level.'
    when 422
      error_msg = response.body['message'] || 'Invalid request parameters'
      raise StandardError, "Alpaca API validation error: #{error_msg}"
    when 429
      raise StandardError, 'Alpaca API rate limit exceeded. Please retry later.'
    else
      error_msg = response.body['message'] || 'Unknown error'
      raise StandardError, "Alpaca API error (#{response.status}): #{error_msg}"
    end
  end

  def parse_bars_response(response_body, symbol) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    bars_data = response_body['bars'] || []

    bars_data.map do |bar|
      {
        symbol: symbol,
        timestamp: Time.zone.parse(bar['t']),
        open: BigDecimal(bar['o'].to_s),
        high: BigDecimal(bar['h'].to_s),
        low: BigDecimal(bar['l'].to_s),
        close: BigDecimal(bar['c'].to_s),
        volume: bar['v'].to_i
      }
    end
  rescue StandardError => e
    Rails.logger.error("Failed to parse Alpaca response for #{symbol}: #{e.message}")
    Rails.logger.error("Response body: #{response_body}")
    raise StandardError, "Failed to parse Alpaca API response: #{e.message}"
  end

  def handle_api_error(error, symbol)
    error_msg = case error
                when Faraday::TimeoutError
                  "Alpaca API timeout for #{symbol}"
                when Faraday::ConnectionFailed
                  "Failed to connect to Alpaca API for #{symbol}"
                else
                  "Alpaca API network error for #{symbol}: #{error.message}"
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
    @api_key ||= fetch_credential('ALPACA_API_KEY', 'test-api-key')
  end

  def secret_key
    @secret_key ||= fetch_credential('ALPACA_SECRET_KEY', 'test-secret-key')
  end

  def fetch_credential(env_var, default_value)
    # Try environment variable first
    env_value = ENV.fetch(env_var, nil)
    return env_value if env_value.present?

    # Try Rails credentials second
    credentials_value = Rails.application.credentials.dig(:alpaca, env_var.downcase.to_sym)
    return credentials_value if credentials_value.present?

    # Use default for development/test
    if Rails.env.local?
      Rails.logger.warn("Using default #{env_var} for #{Rails.env} environment")
      return default_value
    end

    # Fail in production without real credentials
    raise StandardError, "Missing required Alpaca credential: #{env_var}"
  end
end
