# frozen_string_literal: true

# RebalanceToTarget Command
#
# This command is responsible for making the current portfolio match the target state
# defined by the strategy. It executes trades to align the current portfolio with
# the target positions.
#
# Responsibilities:
# 1. Call the AlpacaService to get all current positions
# 2. Compare current positions against target portfolio to calculate deltas
# 3. First, execute all sell orders for positions no longer in target portfolio
# 4. Then, execute all buy/adjustment orders using notional values
# 5. Log every placed order by creating an AlpacaOrder record
# 6. Only handle stock asset types initially (raise NotImplementedError for others)
module Trades
  class RebalanceToTarget < GLCommand::Callable
    requires :target
    returns :orders_placed

    validate :validate_target_is_array
    validate :validate_target_positions
    validate :validate_asset_types

    def call
      context.orders_placed = []

      # Step 0: Cancel any existing open orders to avoid conflicts
      cancel_open_orders

      current_positions = fetch_current_positions
      target_positions_by_symbol = index_target_positions_by_symbol

      # Step 1: Execute sell orders for positions not in target
      execute_sell_orders(current_positions, target_positions_by_symbol)

      # Step 2: Execute buy/adjustment orders for target positions
      execute_buy_orders(target_positions_by_symbol, current_positions)
    end

    private

    def cancel_open_orders
      alpaca_service = AlpacaService.new
      canceled_count = alpaca_service.cancel_all_orders
      Rails.logger.info("Canceled #{canceled_count} open orders before rebalancing") if canceled_count > 0
    rescue StandardError => e
      Rails.logger.warn("Failed to cancel open orders: #{e.message}")
      # Don't fail the command, just warn - we'll try to place orders anyway
    end

    def validate_target_is_array
      return if context.target.nil?

      errors.add(:target, 'must be an array') unless context.target.is_a?(Array)
    end

    def validate_target_positions
      return unless context.target.is_a?(Array)

      context.target.each_with_index do |position, index|
        unless position.is_a?(TargetPosition)
          errors.add(:target, "position at index #{index} must be a TargetPosition object")
        end
      end
    end

    def validate_asset_types
      return unless context.target.is_a?(Array)

      context.target.each do |position|
        next unless position.is_a?(TargetPosition)

        unless position.asset_type == :stock
          raise NotImplementedError,
                "Asset type #{position.asset_type} is not supported. Only :stock is currently supported."
        end
      end
    end

    def fetch_current_positions
      alpaca_service = AlpacaService.new
      alpaca_service.current_positions
    rescue StandardError => e
      stop_and_fail!("Failed to fetch current positions: #{e.message}")
    end

    def index_target_positions_by_symbol
      context.target.index_by(&:symbol)
    end

    def execute_sell_orders(current_positions, target_positions_by_symbol)
      positions_to_sell = current_positions.reject do |position|
        target_positions_by_symbol.key?(position[:symbol])
      end

      positions_to_sell.each do |position|
        place_sell_order(position)
      end
    end

    def execute_buy_orders(target_positions_by_symbol, current_positions)
      current_positions_by_symbol = current_positions.index_by { |pos| pos[:symbol] }

      target_positions_by_symbol.each_value do |target_position|
        current_position = current_positions_by_symbol[target_position.symbol]
        place_buy_or_adjustment_order(target_position, current_position)
      end
    end

    def place_sell_order(position)
      alpaca_service = AlpacaService.new

      # For selling entire positions, use notional value rounded to 2 decimal places
      # This ensures we sell essentially everything we have without fractional share precision issues
      notional_value = position[:market_value].round(2)
      
      order_response = alpaca_service.place_order(
        symbol: position[:symbol],
        side: 'sell',
        notional: notional_value
      )

      create_alpaca_order_record(order_response, position[:symbol], 'sell', notional: notional_value)
      context.orders_placed << order_response

      Rails.logger.info("Placed sell order for #{position[:symbol]}: $#{notional_value} (~#{position[:qty]} shares)")
    rescue StandardError => e
      Rails.logger.error("Failed to place sell order for #{position[:symbol]}: #{e.message}")
      stop_and_fail!("Failed to place sell order for #{position[:symbol]}: #{e.message}")
    end

    def place_buy_or_adjustment_order(target_position, current_position)
      # Calculate the notional amount needed to reach target
      current_value = current_position&.dig(:market_value) || BigDecimal('0')
      target_value = target_position.target_value

      # If current value equals target value (within a small tolerance), skip
      tolerance = BigDecimal('0.01') # $0.01 tolerance
      return if (current_value - target_value).abs <= tolerance

      alpaca_service = AlpacaService.new

      side = target_value > current_value ? 'buy' : 'sell'
      notional_amount = (target_value - current_value).abs

      order_response = alpaca_service.place_order(
        symbol: target_position.symbol,
        side: side,
        notional: notional_amount
      )

      create_alpaca_order_record(order_response, target_position.symbol, side, notional: notional_amount)
      context.orders_placed << order_response

      Rails.logger.info("Placed #{side} order for #{target_position.symbol}: $#{notional_amount}")
    rescue StandardError => e
      Rails.logger.error("Failed to place #{side} order for #{target_position.symbol}: #{e.message}")
      stop_and_fail!("Failed to place order for #{target_position.symbol}: #{e.message}")
    end

    def create_alpaca_order_record(order_response, symbol, side, qty: nil, notional: nil)
      AlpacaOrder.create!(
        alpaca_order_id: order_response[:id],
        symbol: symbol,
        side: side,
        status: order_response[:status],
        qty: qty,
        notional: notional,
        order_type: 'market',
        time_in_force: 'day',
        submitted_at: order_response[:submitted_at]
      )
    rescue StandardError => e
      Rails.logger.error("Failed to create AlpacaOrder record: #{e.message}")
      # Don't fail the command for logging errors, but log the issue
    end
  end
end
