# frozen_string_literal: true

# AlpacaApiClient
#
# Service for interacting with the Alpaca Market Data API
# Handles authentication, rate limiting, and data formatting
class AlpacaApiClient
  # API configuration
  API_VERSION = 'v2'
  TIMEOUT = 30

  # Rate limiting
  MAX_REQUESTS_PER_MINUTE = 180
  REQUEST_INTERVAL = 60.0 / MAX_REQUESTS_PER_MINUTE

  def initialize(environment: :paper) # Default to paper trading
    @config = fetch_config(environment)
    @last_request_time = 0
    @connection = build_connection
  end

  # Fetch historical bars for a symbol within a date range
  # Returns array of hashes with bar data
  def fetch_bars(symbols, start_date, end_date)
    rate_limit

    params = {
      start: start_date.strftime('%Y-%m-%d'),
      end: end_date.strftime('%Y-%m-%d'),
      timeframe: '1Day',
      adjustment: 'raw',
      feed: 'iex' # Use IEX feed for free tier
    }

    if symbols.is_a?(Array)
      path = "/#{API_VERSION}/stocks/bars"
      params[:symbols] = symbols.join(',')
      Rails.logger.info("Fetching bars for #{symbols.join(', ')} from #{start_date} to #{end_date}")
    else
      path = "/#{API_VERSION}/stocks/#{symbols}/bars"
      Rails.logger.info("Fetching bars for #{symbols} from #{start_date} to #{end_date}")
    end

    response = @connection.get(path, params)
    handle_response(response, symbols)
  rescue Faraday::Error => e
    handle_api_error(e, symbols)
  end

  private

  def build_connection
    Faraday.new(
      url: 'https://data.alpaca.markets', # Always use the data API endpoint
      headers: {
        'APCA-API-KEY-ID' => @config.fetch(:api_key),
        'APCA-API-SECRET-KEY' => @config.fetch(:secret_key),
        'Content-Type' => 'application/json'
      }
    ) do |f|
      f.request :retry, {
        max: 5,
        retry_if: ->(env, _exc) { env&.response&.status == 429 },
        retry_block: lambda do |env, _options, _retries, _exception|
                       response = env&.response
                       if response
                         reset_time = response.headers['X-RateLimit-Reset']
                         if reset_time
                           sleep_duration = reset_time.to_i - Time.now.to_i
                           if sleep_duration.positive?
                             Rails.logger.warn("Rate limit hit. Sleeping for #{sleep_duration} seconds until #{Time.at(reset_time.to_i)}.")
                             sleep sleep_duration
                           end
                         else
                           sleep 1 # Default sleep of 1 second if header is not present
                         end
                       end
                     end
      }
      f.adapter :net_http
      f.options.timeout = TIMEOUT
      f.options.open_timeout = 10
    end
  end

  def fetch_config(environment)
    config = Rails.application.credentials.dig(:alpaca, environment)

    unless config && config[:alpaca_api_key] && config[:alpaca_api_secret]
      raise StandardError, "Missing or incomplete Alpaca configuration for environment: #{environment}"
    end

    {
      api_key: config[:alpaca_api_key],
      secret_key: config[:alpaca_api_secret]
    }
  end

  def handle_response(response, symbols)
    parsed_body = response.body.is_a?(String) ? JSON.parse(response.body) : response.body

    case response.status
    when 200
      parse_bars_response(parsed_body, symbols)
    when 401
      error_body = response.body.is_a?(String) ? response.body : parsed_body.to_json
      raise StandardError, "Alpaca API authentication failed. Check your API credentials. Response: #{error_body}"
    else
      error_msg = parsed_body.is_a?(Hash) ? (parsed_body['message'] || 'Unknown error') : parsed_body
      Rails.logger.error("Alpaca API Raw Response: #{response.body}")
      raise StandardError, "Alpaca API error (#{response.status}): #{error_msg}"
    end
  rescue JSON::ParserError => e
    raise StandardError, "Failed to parse Alpaca API response: #{e.message}"
  end

  def parse_bars_response(response_body, symbols)
    if symbols.is_a?(Array)
      # Multi-symbol response is a hash of symbol -> bars
      response_body.flat_map do |symbol, bars|
        (bars || []).map do |bar|
          format_bar(bar, symbol)
        end.compact
      end
    else
      # Single-symbol response has a 'bars' key
      bars_data = response_body['bars'] || []
      bars_data.map do |bar|
        format_bar(bar, symbols)
      end.compact
    end
  end

  def format_bar(bar, symbol)
    return nil unless bar.is_a?(Hash)

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

  def handle_api_error(error, symbols)
    symbol_str = symbols.is_a?(Array) ? symbols.join(', ') : symbols
    error_msg = case error
                when Faraday::TimeoutError
                  "Alpaca API timeout for #{symbol_str}"
                when Faraday::TooManyRequestsError
                  "Alpaca API rate limit exceeded for #{symbol_str}, even after retries."
                else
                  "Alpaca API network error for #{symbol_str}: #{error.message}"
                end
    raise StandardError, error_msg
  end

  def rate_limit
    current_time = Time.current.to_f
    time_since_last_request = current_time - @last_request_time
    if time_since_last_request < REQUEST_INTERVAL
      sleep_time = REQUEST_INTERVAL - time_since_last_request
      sleep(sleep_time)
    end
    @last_request_time = Time.current.to_f
  end
end