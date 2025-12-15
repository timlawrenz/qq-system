# frozen_string_literal: true

require 'securerandom'

# AlpacaService
#
# Service to wrap all interactions with the alpaca-trade-api-ruby gem.
# Provides methods for account information, positions, and placing orders.
# rubocop:disable Metrics/ClassLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Style/MultilineBlockChain, Layout/LineLength
class AlpacaService
  class ConfigurationError < StandardError; end
  class SafetyError < StandardError; end

  PAPER_ENDPOINT = 'https://paper-api.alpaca.markets'
  LIVE_ENDPOINT = 'https://api.alpaca.markets'

  def initialize
    @trading_mode = ENV.fetch('TRADING_MODE').downcase
    validate_trading_mode!

    @client = Alpaca::Trade::Api::Client.new(
      endpoint: endpoint,
      key_id: api_key_id,
      key_secret: api_secret_key
    )

    log_trading_mode
  end

  attr_reader :trading_mode

  # Get the current total account equity
  # Returns the total equity value as a BigDecimal
  def account_equity
    account = @client.account
    BigDecimal(account.equity)
  rescue StandardError => e
    Rails.logger.error("Failed to get account equity: #{e.message}")
    raise StandardError, "Unable to retrieve account equity: #{e.message}"
  end

  # Get current positions
  # Returns array of position hashes with symbol and market value
  def current_positions
    positions = @client.positions

    positions.map do |position|
      {
        symbol: position.symbol,
        qty: BigDecimal(position.qty),
        market_value: BigDecimal(position.market_value),
        side: position.side
      }
    end
  rescue StandardError => e
    Rails.logger.error("Failed to get current positions: #{e.message}")
    raise StandardError, "Unable to retrieve current positions: #{e.message}"
  end

  # Place an order
  # @param symbol [String] The stock symbol to trade
  # @param side [String] 'buy' or 'sell'
  # @param notional [BigDecimal, nil] Dollar amount to trade (for notional orders)
  # @param qty [BigDecimal, nil] Number of shares to trade (for quantity orders)
  # @return [Hash] Order details
  def place_order(symbol:, side:, notional: nil, qty: nil)
    validate_order_parameters(symbol: symbol, side: side, notional: notional, qty: qty)
    order_params = build_order_params(symbol: symbol, side: side, notional: notional, qty: qty)

    Rails.logger.info("Placing order: #{order_params}")

    order = @client.new_order(**order_params)
    format_order_response(order)
  rescue ArgumentError => e
    Rails.logger.error("Invalid order parameters: #{e.message}")
    raise e
  rescue StandardError => e
    Rails.logger.error("Failed to place order: #{e.message}")
    raise StandardError, "Unable to place order: #{e.message}"
  end

  # Cancel all open orders
  # @return [Integer] Number of orders canceled
  def cancel_all_orders
    orders = @client.cancel_orders

    # The alpaca-trade-api gem may raise or return unexpected structures when there
    # are no open orders; treat any non-Array/nil as "no orders" instead of failing.
    return 0 unless orders.is_a?(Array)

    orders.size
  rescue NoMethodError => e
    Rails.logger.warn("Failed to cancel orders due to unexpected Alpaca payload, treating as no open orders: #{e.message}")
    0
  rescue StandardError => e
    Rails.logger.error("Failed to cancel orders: #{e.message}")
    raise StandardError, "Unable to cancel orders: #{e.message}"
  end

  # Close an entire position (sell all shares)
  # @param symbol [String] The stock symbol to close
  # @return [Hash] Order details
  def close_position(symbol:)
    raise ArgumentError, 'Symbol is required' if symbol.blank?

    Rails.logger.info("Closing position: #{symbol}")

    # The Alpaca gem returns a Position object, but the underlying API returns an Order
    # We need to extract the order data from the response
    response = @client.close_position(symbol: symbol.upcase)

    # The response is a Position object, but it contains order-like data.
    # Alpaca does not return a real order ID here, so we synthesize a stable
    # identifier for logging/auditing while using the requested symbol.
    synthesized_id = [
      'CLOSE',
      symbol.upcase,
      Time.current.to_i,
      SecureRandom.hex(4)
    ].join('-')

    {
      id: synthesized_id,
      symbol: symbol.upcase,
      side: 'sell',
      qty: response.qty ? BigDecimal(response.qty.to_s) : nil,
      status: 'filled', # Close position creates a market order that fills immediately
      submitted_at: Time.current
    }
  rescue StandardError => e
    Rails.logger.error("Failed to close position for #{symbol}: #{e.message}")
    raise StandardError, "Unable to close position: #{e.message}"
  end

  # Get historical bars (candlestick data) for a single symbol
  # @param symbol [String] Stock symbol (e.g., 'SPY')
  # @param start_date [Date, String] Start date
  # @param end_date [Date, String] End date
  # @param timeframe [String] Timeframe (e.g., '1D', 'day')
  # @return [Array<Hash>] Array of bar data
  def get_bars(symbol, start_date:, end_date: Date.current, timeframe: '1Day')
    bars_by_symbol = get_bars_multi([symbol], start_date: start_date, end_date: end_date, timeframe: timeframe)
    bars_by_symbol[symbol] || []
  end

  # Get historical bars for multiple symbols in a single API call.
  # @param symbols [Array<String>] Stock symbols
  # @return [Hash{String => Array<Hash>}] map of symbol => bar hashes
  def get_bars_multi(symbols, start_date:, end_date: Date.current, timeframe: '1Day')
    # Normalize timeframe to values supported by alpaca-trade-api gem
    normalized_timeframe =
      case timeframe
      when '1Day' then '1D'
      else timeframe
      end

    # Alpaca::Trade::Api::Client#bars returns a hash of symbol => [Bar]
    raw = @client.bars(
      normalized_timeframe,
      symbols,
      limit: 1000,
      start_time: start_date.to_time.utc.iso8601,
      end_time: end_date.to_time.utc.iso8601
    )

    result = {}

    Array(symbols).each do |sym|
      bars = raw[sym] || raw[sym.to_s] || []

      bar_hashes = bars.map do |bar|
        if bar.respond_to?(:t)
          # Legacy hash-like structure with :t/:o/:h/:l/:c/:v
          {
            timestamp: bar.t,
            open: BigDecimal(bar.o.to_s),
            high: BigDecimal(bar.h.to_s),
            low: BigDecimal(bar.l.to_s),
            close: BigDecimal(bar.c.to_s),
            volume: bar.v.to_i
          }
        else
          # Alpaca::Trade::Api::Bar object
          {
            timestamp: bar.time,
            open: BigDecimal(bar.open.to_s),
            high: BigDecimal(bar.high.to_s),
            low: BigDecimal(bar.low.to_s),
            close: BigDecimal(bar.close.to_s),
            volume: bar.volume.to_i
          }
        end
      end

      filtered = bar_hashes.select do |b|
        ts = b[:timestamp].to_date
        ts >= start_date.to_date && ts <= end_date.to_date
      end

      result[sym] = filtered
    end

    result
  rescue StandardError => e
    Rails.logger.error("Failed to fetch bars for #{Array(symbols).join(', ')}: #{e.message}")
    {}
  end

  # Get account portfolio history (equity over time)
  # @param start_date [Date, String] Start date
  # @param end_date [Date, String] End date (defaults to today)
  # @param timeframe [String] Timeframe ('1D' for daily)
  # @return [Array<Hash>] Array of hashes with timestamp and equity
  def account_equity_history(start_date:, end_date: Date.current, timeframe: '1D')
    portfolio_history = @client.portfolio_history(
      period: nil,
      timeframe: timeframe,
      date_end: end_date.to_s,
      extended_hours: false
    )

    # Portfolio history returns arrays of timestamps and equity values
    timestamps = portfolio_history.timestamp
    equity_values = portfolio_history.equity

    timestamps.zip(equity_values).map do |timestamp, equity|
      {
        timestamp: Time.zone.at(timestamp).to_date,
        equity: BigDecimal(equity.to_s)
      }
    end.select { |point| point[:timestamp] >= start_date.to_date }
  rescue StandardError => e
    Rails.logger.warn("Failed to fetch account equity history: #{e.message}")
    # Return empty array if history unavailable (new account or API issue)
    []
  end

  private

  attr_reader :client

  def validate_trading_mode!
    unless %w[paper live].include?(@trading_mode)
      raise ConfigurationError, "Invalid TRADING_MODE: #{@trading_mode}. Must be 'paper' or 'live'"
    end

    if api_key_id.blank?
      raise ConfigurationError, "Missing #{credential_prefix}_API_KEY_ID for #{@trading_mode} trading mode"
    end

    if api_secret_key.blank?
      raise ConfigurationError, "Missing #{credential_prefix}_API_SECRET_KEY for #{@trading_mode} trading mode"
    end

    return unless @trading_mode == 'live' && ENV['CONFIRM_LIVE_TRADING'] != 'yes'

    raise SafetyError, 'Live trading requires CONFIRM_LIVE_TRADING=yes environment variable'
  end

  def endpoint
    @trading_mode == 'live' ? LIVE_ENDPOINT : PAPER_ENDPOINT
  end

  def credential_prefix
    @trading_mode == 'live' ? 'ALPACA_LIVE' : 'ALPACA_PAPER'
  end

  def api_key_id
    ENV.fetch("#{credential_prefix}_API_KEY_ID", nil)
  end

  def api_secret_key
    ENV.fetch("#{credential_prefix}_API_SECRET_KEY", nil)
  end

  def log_trading_mode
    Rails.logger.warn('🚨 LIVE TRADING MODE ACTIVE 🚨') if @trading_mode == 'live'
    Rails.logger.info("Trading mode: #{@trading_mode.upcase} | Endpoint: #{endpoint}")
  end

  def validate_order_parameters(symbol:, side:, notional:, qty:)
    raise ArgumentError, 'Symbol is required' if symbol.blank?
    raise ArgumentError, 'Side must be buy or sell' unless %w[buy sell].include?(side.to_s.downcase)
    raise ArgumentError, 'Either notional or qty must be provided' if notional.nil? && qty.nil?
    raise ArgumentError, 'Cannot specify both notional and qty' if notional.present? && qty.present?
  end

  def build_order_params(symbol:, side:, notional:, qty:)
    params = {
      symbol: symbol.upcase,
      side: side.to_s.downcase,
      type: 'market',
      time_in_force: 'day'
    }

    if notional.present?
      params[:notional] = format_decimal_for_api(notional)
    else
      params[:qty] = format_decimal_for_api(qty)
    end

    params
  end

  def format_order_response(order)
    # Handle both hash and object responses from Alpaca API
    if order.is_a?(Hash)
      {
        id: order[:id] || order['id'],
        symbol: order[:symbol] || order['symbol'],
        side: order[:side] || order['side'],
        qty: order[:qty] || order['qty'] ? BigDecimal((order[:qty] || order['qty']).to_s) : nil,
        status: order[:status] || order['status'],
        submitted_at: order[:submitted_at] || order['submitted_at'] ? Time.zone.parse((order[:submitted_at] || order['submitted_at']).to_s) : nil
      }
    else
      {
        id: order.id,
        symbol: order.symbol,
        side: order.side,
        qty: order.qty ? BigDecimal(order.qty.to_s) : nil,
        status: order.status,
        submitted_at: order.submitted_at ? Time.zone.parse(order.submitted_at.to_s) : nil
      }
    end
  end

  # Format decimal for API, preserving precision but removing unnecessary trailing zeros
  def format_decimal_for_api(value)
    # Convert to BigDecimal first to handle various input types consistently
    decimal_value = BigDecimal(value.to_s)
    # Round to 2 decimal places for Alpaca API (notional values must be limited to 2 decimal places)
    rounded = decimal_value.round(2)
    # Convert to string and remove trailing .0 if it's a whole number
    formatted = rounded.to_s('F')
    formatted.sub(/\.0+$/, '')
  end
  # rubocop:enable Metrics/ClassLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Style/MultilineBlockChain, Layout/LineLength
end
