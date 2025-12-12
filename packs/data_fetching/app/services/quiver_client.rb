# frozen_string_literal: true

require 'faraday'

# QuiverClient
#
# Service for interacting with the Quiver Quantitative API
# Handles authentication, rate limiting, and data formatting for:
# - Congressional trades (Tier 1)
# - Corporate lobbying data (Tier 2)
# rubocop:disable Metrics/ClassLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
class QuiverClient
  # API configuration
  BASE_URL = 'https://api.quiverquant.com'
  API_VERSION = 'beta'
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

    path = "/#{API_VERSION}/bulk/congresstrading"
    params = build_params(options)

    Rails.logger.info("Fetching congressional trades from Quiver API with params: #{params}")

    begin
      response = @connection.get(path, params)
      handle_response(response, options)
    rescue Faraday::Error => e
      handle_api_error(e)
    end
  end

  # Fetch corporate insider trades from Quiver API
  # Returns array of hashes with insider trading data
  def fetch_insider_trades(options = {})
    rate_limit

    path = "/#{API_VERSION}/live/insiders"
    params = build_params(options)

    Rails.logger.info("Fetching insider trades from Quiver API with params: #{params}")

    begin
      response = @connection.get(path, params)
      handle_insider_response(response, options)
    rescue Faraday::Error => e
      handle_api_error(e)
    end
  end

  # Fetch lobbying data for a specific ticker from Quiver API
  # Returns array of hashes with lobbying disclosure data
  # @param ticker [String] Stock ticker symbol (e.g., 'GOOGL')
  # @return [Array<Hash>] Array of lobbying records
  def fetch_lobbying_data(ticker)
    rate_limit

    path = "/#{API_VERSION}/historical/lobbying/#{ticker}"

    Rails.logger.info("Fetching lobbying data for #{ticker}")

    begin
      response = @connection.get(path)
      handle_lobbying_response(response, ticker)
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

  def handle_response(response, options = {})
    # Handle auth failure before parsing
    if [401, 500].include?(response.status)
      raise StandardError,
            'Quiver API authentication failed. Check your API credentials.'
    end

    # Parse JSON response body
    parsed_body = JSON.parse(response.body)

    case response.status
    when 200
      parse_trades_response(parsed_body, options)
    when 403
      raise StandardError, 'Quiver API access forbidden. Check your subscription level.'
    when 422
      error_msg = parsed_body['message'] || 'Invalid request parameters'
      raise StandardError, "Quiver API validation error: #{error_msg}"
    when 429
      raise StandardError, 'Quiver API rate limit exceeded. Please retry later.'
    else
      error_msg = parsed_body.is_a?(Hash) ? (parsed_body['message'] || 'Unknown error') : parsed_body
      raise StandardError, "Quiver API error (#{response.status}): #{error_msg}"
    end
  rescue JSON::ParserError => e
    raise StandardError, "Failed to parse Quiver API response: #{e.message}"
  end

  def parse_trades_response(response_body, _options = {})
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
        ticker: trade['Ticker'],
        company: trade['Company'],
        trader_name: trade['Name'],
        trader_source: 'congress',
        transaction_date: parse_date(trade['Traded']),
        transaction_type: trade['Transaction'],
        trade_size_usd: trade['Trade_Size_USD'],
        disclosed_at: parse_datetime(trade['Filed'])
      }
    end
  rescue StandardError => e
    Rails.logger.error("Failed to parse Quiver trades response: #{e.message}")
    []
  end

  def handle_insider_response(response, options = {})
    if [401, 500].include?(response.status)
      raise StandardError,
            'Quiver API authentication failed. Check your API credentials.'
    end

    parsed_body = JSON.parse(response.body)

    case response.status
    when 200
      parse_insider_trades_response(parsed_body, options)
    when 403
      raise StandardError, 'Quiver API access forbidden. Check Tier 2 access for insider data.'
    when 422
      error_msg = parsed_body['message'] || 'Invalid request parameters'
      raise StandardError, "Quiver API validation error: #{error_msg}"
    when 429
      raise StandardError, 'Quiver API rate limit exceeded. Please retry later.'
    else
      error_msg = parsed_body.is_a?(Hash) ? (parsed_body['message'] || 'Unknown error') : parsed_body
      raise StandardError, "Quiver API error (#{response.status}): #{error_msg}"
    end
  rescue JSON::ParserError => e
    raise StandardError, "Failed to parse Quiver API response: #{e.message}"
  end

  def handle_lobbying_response(response, ticker)
    case response.status
    when 200
      parse_lobbying_data(response.body, ticker)
    when 404
      Rails.logger.info("No lobbying data found for #{ticker}")
      []
    when 403
      raise StandardError, 'Quiver API access forbidden. Check Tier 2 access.'
    when 401, 500
      raise StandardError, 'Quiver API authentication failed. Check your API credentials.'
    when 429
      raise StandardError, 'Quiver API rate limit exceeded. Please retry later.'
    else
      raise StandardError, "Quiver API error (#{response.status})"
    end
  rescue JSON::ParserError => e
    raise StandardError, "Failed to parse Quiver API response: #{e.message}"
  end

  def parse_insider_trades_response(response_body, _options = {})
    trades_data = if response_body.is_a?(Hash) && response_body['data']
                    response_body['data']
                  elsif response_body.is_a?(Array)
                    response_body
                  else
                    []
                  end

    return [] unless trades_data.is_a?(Array)

    trades_data.filter_map do |trade|
      # Skip records with missing required fields
      next if trade['Ticker'].blank?
      next if trade['Name'].blank?
      next if trade['Date'].blank?

      # Determine transaction type from codes
      # AcquiredDisposedCode: A = Acquired, D = Disposed
      # TransactionCode: P = Purchase, S = Sale, A = Award/Grant, etc.
      transaction_type = determine_transaction_type(
        trade['AcquiredDisposedCode'],
        trade['TransactionCode']
      )

      # Skip if we can't determine transaction type
      next if transaction_type.blank?

      # Determine relationship from officer/director flags
      relationship = determine_relationship(trade)

      # Calculate trade value
      shares = trade['Shares'].to_f
      price = trade['PricePerShare'].to_f
      trade_value = shares * price

      {
        ticker: trade['Ticker'],
        company: nil, # Not provided by this endpoint
        trader_name: trade['Name'],
        trader_source: 'insider',
        transaction_date: parse_date(trade['Date']),
        transaction_type: transaction_type,
        trade_size_usd: trade_value.to_s,
        disclosed_at: parse_datetime(trade['fileDate']),
        relationship: relationship,
        shares_held: trade['SharesOwnedFollowing'].to_i,
        ownership_percent: nil # Can calculate if needed
      }
    end
  rescue StandardError => e
    Rails.logger.error("Failed to parse insider trades response: #{e.message}")
    []
  end

  def determine_transaction_type(acquired_disposed, transaction_code)
    # AcquiredDisposedCode: A = Acquired, D = Disposed
    case acquired_disposed
    when 'A'
      'Purchase'
    when 'D'
      'Sale'
    else
      # Fallback to transaction code
      case transaction_code
      when 'P'
        'Purchase'
      when 'S'
        'Sale'
      else
        'Other'
      end
    end
  end

  def determine_relationship(trade)
    title = trade['officerTitle']
    return title if title.present?

    # Determine from flags
    relationships = []
    relationships << 'Director' if trade['isDirector']
    relationships << 'Officer' if trade['isOfficer']
    relationships << '10% Owner' if trade['isTenPercentOwner']

    relationships.any? ? relationships.join(', ') : 'Other'
  end

  def parse_lobbying_data(body, ticker)
    data = JSON.parse(body)
    return [] unless data.is_a?(Array)

    data.map do |record|
      {
        ticker: ticker,
        date: parse_date(record['Date']),
        quarter: extract_quarter(record),
        amount: parse_amount(record['Amount']),
        client: record['Client'],
        issue: record['Issue'],
        specific_issue: record['Specific_Issue'],
        registrant: record['Registrant']
      }
    end
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse lobbying data: #{e.message}")
    []
  rescue StandardError => e
    Rails.logger.error("Error processing lobbying data for #{ticker}: #{e.message}")
    []
  end

  def extract_quarter(record)
    # Try 'Quarter' field first, fallback to calculating from 'Date'
    return record['Quarter'] if record['Quarter'].present?

    date = parse_date(record['Date'])
    return nil if date.nil?

    quarter_num = ((date.month - 1) / 3) + 1
    "Q#{quarter_num} #{date.year}"
  end

  def normalize_transaction_type(transaction)
    return nil if transaction.blank?

    case transaction.to_s.downcase
    when /purchase|buy/
      'Purchase'
    when /sale|sell/
      'Sale'
    else
      transaction.to_s
    end
  end

  def parse_trade_value(value)
    return nil if value.blank?

    value.to_s.gsub(/[,$]/, '').to_f
  end

  def parse_integer(value)
    return nil if value.blank?

    value.to_s.delete(',').to_i
  end

  def parse_percent(percent_string)
    return nil if percent_string.blank?

    percent_string.to_s.delete('%').to_f
  end

  def parse_amount(amount_string)
    return nil if amount_string.blank?

    # Remove currency symbols, commas, and convert to float
    amount_string.to_s.gsub(/[,$]/, '').to_f
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
    @api_key ||= fetch_credential('QUIVER_AUTH_TOKEN', 'test-api-key')
  end

  def fetch_credential(env_var, default_value)
    # Try environment variable first
    env_value = ENV.fetch(env_var, nil)
    return env_value if env_value.present?

    # Try Rails credentials second
    credentials_value = Rails.application.credentials.dig(:quiverquant, :auth_token)
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
# rubocop:enable Metrics/ClassLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
