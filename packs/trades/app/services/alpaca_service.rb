# frozen_string_literal: true

# AlpacaService
#
# Service to wrap all interactions with the alpaca-trade-api-ruby gem.
# Provides methods for account information, positions, and placing orders.
class AlpacaService
  def initialize
    @client = Alpaca::Trade::Api::Client.new
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
    {
      id: order.id,
      symbol: order.symbol,
      side: order.side,
      qty: order.qty ? BigDecimal(order.qty) : nil,
      notional: order.notional ? BigDecimal(order.notional) : nil,
      status: order.status,
      submitted_at: order.submitted_at ? Time.zone.parse(order.submitted_at) : nil
    }
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
