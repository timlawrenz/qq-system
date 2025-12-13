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
      Rails.logger.info("Canceled #{canceled_count} open orders before rebalancing") if canceled_count.positive?
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

      # Use Alpaca's close_position endpoint to sell the entire position
      # This avoids fractional share precision issues with notional orders
      order_response = alpaca_service.close_position(symbol: position[:symbol])

      create_alpaca_order_record(order_response, position[:symbol], 'sell', qty: position[:qty])
      context.orders_placed << order_response

      Rails.logger.info("Placed sell order to close position for #{position[:symbol]}: #{position[:qty]} shares")
    rescue StandardError => e
      # Handle inactive/non-tradable assets gracefully - skip and continue
      if /asset .+ is not active|not tradable/i.match?(e.message)
        Rails.logger.warn("Skipped sell order for #{position[:symbol]}: asset not active or not tradable")
        BlockedAsset.block_asset(symbol: position[:symbol], reason: 'asset_not_active')
        context.orders_placed << {
          symbol: position[:symbol],
          side: 'sell',
          status: 'skipped',
          reason: 'asset_not_active'
        }
      else
        Rails.logger.error("Failed to place sell order for #{position[:symbol]}: #{e.message}")
        stop_and_fail!("Failed to place sell order for #{position[:symbol]}: #{e.message}")
      end
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
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

      # Skip very small adjustments (less than $1.00 to avoid Alpaca minimum)
      if notional_amount < 1.0
        msg = "Skipping #{side} order for #{target_position.symbol}: " \
              "amount $#{notional_amount.round(2)} below $1.00 minimum"
        Rails.logger.info(msg)
        return
      end

      order_response = alpaca_service.place_order(
        symbol: target_position.symbol,
        side: side,
        notional: notional_amount
      )

      create_alpaca_order_record(order_response, target_position.symbol, side, notional: notional_amount)
      context.orders_placed << order_response

      Rails.logger.info("Placed #{side} order for #{target_position.symbol}: $#{notional_amount}")
    rescue StandardError => e
      # Handle insufficient buying power gracefully - this is expected with small accounts
      if /insufficient buying power|insufficient funds/i.match?(e.message)
        msg = "Skipped #{side} order for #{target_position.symbol} " \
              "($#{notional_amount.round(2)}): insufficient buying power"
        Rails.logger.warn(msg)
        context.orders_placed << {
          symbol: target_position.symbol,
          side: side,
          status: 'skipped',
          reason: 'insufficient_buying_power',
          attempted_amount: notional_amount.round(2)
        }
      elsif /asset .+ is not active|not tradable|not fractionable/i.match?(e.message)
        # Handle inactive/non-tradable assets gracefully - skip and continue
        msg = "Skipped #{side} order for #{target_position.symbol} " \
              "($#{notional_amount.round(2)}): asset not active or not tradable"
        Rails.logger.warn(msg)
        BlockedAsset.block_asset(symbol: target_position.symbol, reason: 'asset_not_active')
        context.orders_placed << {
          symbol: target_position.symbol,
          side: side,
          status: 'skipped',
          reason: 'asset_not_active',
          attempted_amount: notional_amount.round(2)
        }
      else
        # For other errors, still fail the command
        Rails.logger.error("Failed to place #{side} order for #{target_position.symbol}: #{e.message}")
        stop_and_fail!("Failed to place order for #{target_position.symbol}: #{e.message}")
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def create_alpaca_order_record(order_response, symbol, side, qty: nil, notional: nil)
      # Some Alpaca endpoints (like close_position) don't return a real order ID.
      # Synthesize a unique identifier when missing so logging/auditing still works.
      alpaca_id = order_response[:id].presence || SecureRandom.uuid

      AlpacaOrder.create!(
        alpaca_order_id: alpaca_id,
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
