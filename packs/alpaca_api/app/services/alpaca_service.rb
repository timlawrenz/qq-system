# frozen_string_literal: true

# AlpacaService
#
# Service to wrap all interactions with the alpaca-trade-api-ruby gem.
# Provides methods for account information, positions, and placing orders.
class AlpacaService
  def initialize
    # Explicitly pass credentials to ensure we use the latest .env values
    # rather than relying on gem's configuration which is initialized at load time
    @client = Alpaca::Trade::Api::Client.new(
      endpoint: ENV['APCA_API_BASE_URL'] || ENV['ALPACA_API_ENDPOINT'] || 'https://paper-api.alpaca.markets',
      key_id: ENV.fetch('ALPACA_API_KEY_ID', nil),
      key_secret: ENV.fetch('ALPACA_API_SECRET_KEY', nil)
    )
  end

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
    orders.size
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

    # The response is a Position object, but it contains order-like data
    # Format it as an order response
    {
      id: response.asset_id, # Use asset_id as order identifier
      symbol: response.symbol,
      side: 'sell',
      qty: response.qty ? BigDecimal(response.qty.to_s) : nil,
      status: 'filled', # Close position creates a market order that fills immediately
      submitted_at: Time.current
    }
  rescue StandardError => e
    Rails.logger.error("Failed to close position for #{symbol}: #{e.message}")
    raise StandardError, "Unable to close position: #{e.message}"
  end

  private

  attr_reader :client

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
    # Convert to string and remove trailing .0 if it's a whole number
    formatted = decimal_value.to_s('F')
    formatted.sub(/\.0+$/, '')
  end
end
