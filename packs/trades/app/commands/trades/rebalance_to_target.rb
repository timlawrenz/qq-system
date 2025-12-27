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
# 5. Log every placed order by creating an AuditTrail::TradeDecision and
#    executing it via AuditTrail::ExecuteTradeDecision.
# 6. Only handle stock asset types initially (raise NotImplementedError for others)
module Trades
  class RebalanceToTarget < GLCommand::Callable
    allows :dry_run
    requires :target
    returns :orders_placed

    validate :validate_target_is_array
    validate :validate_target_positions
    validate :validate_asset_types

    def call
      context.orders_placed = []

      # Step 0: Cancel any existing open orders to avoid conflicts
      cancel_open_orders unless dry_run?

      current_positions = fetch_current_positions
      target_positions_by_symbol = index_target_positions_by_symbol

      # Step 1: Execute sell orders for positions not in target
      execute_sell_orders(current_positions, target_positions_by_symbol)

      # Step 2: Execute buy/adjustment orders for target positions
      execute_buy_orders(target_positions_by_symbol, current_positions)
    end

    private

    def dry_run?
      context.respond_to?(:dry_run) && context.dry_run
    end

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

      # Execute the largest notional adjustments first so small accounts fund the
      # most important trades before buying power runs out.
      sorted_targets = target_positions_by_symbol.values.sort_by do |target_position|
        current_value = current_positions_by_symbol[target_position.symbol]&.dig(:market_value) || BigDecimal('0')
        -(target_position.target_value - current_value).abs
      end

      sorted_targets.each do |target_position|
        current_position = current_positions_by_symbol[target_position.symbol]
        place_buy_or_adjustment_order(target_position, current_position)
      end
    end

    def place_sell_order(position)
      if dry_run?
        order_response = {
          symbol: position[:symbol],
          side: 'sell',
          status: 'planned',
          qty: position[:qty],
          reason: 'plan_only'
        }
        context.orders_placed << order_response
        Rails.logger.info("PLAN ONLY: would close position for #{position[:symbol]}: #{position[:qty]} shares")
        return
      end

      qty = position[:qty].to_f
      is_dust = qty < 0.00000001

      # For dust positions, bypass trade decision validation and directly close via Alpaca
      if is_dust
        Rails.logger.info("Closing dust position #{position[:symbol]}: #{position[:qty]} shares using close_position API (bypassing trade decision)")

        begin
          alpaca_service = AlpacaService.new
          close_result = alpaca_service.close_position(symbol: position[:symbol])

          context.orders_placed << {
            id: close_result[:id],
            symbol: position[:symbol],
            side: 'sell',
            qty: close_result[:qty] || position[:qty],
            status: close_result[:status],
            submitted_at: close_result[:submitted_at]
          }

          Rails.logger.info("Closed dust position #{position[:symbol]}: #{close_result[:qty] || position[:qty]} shares")
        rescue StandardError => e
          Rails.logger.error("Failed to close dust position #{position[:symbol]}: #{e.message}")
          stop_and_fail!("Failed to close dust position #{position[:symbol]}: #{e.message}")
        end
        return
      end

      # 1. Create decision for normal positions
      decision_cmd = AuditTrail::CreateTradeDecision.call(
        strategy_name: 'RebalanceToTarget',
        symbol: position[:symbol],
        side: 'sell',
        quantity: qty,
        rationale: {
          trigger_event: 'rebalance_sell_off',
          portfolio_context: {
            reason: 'position no longer in target'
          }
        }
      )

      if decision_cmd.failure?
        Rails.logger.error("Failed to create trade decision for sell #{position[:symbol]}: #{decision_cmd.errors.full_messages.join(', ')}")
        stop_and_fail!("Failed to create trade decision for sell #{position[:symbol]}")
      end

      # 2. Execute - use close_position to liquidate entire position accurately
      execution_cmd = AuditTrail::ExecuteTradeDecision.call(
        trade_decision: decision_cmd.trade_decision,
        close_position: true
      )

      if execution_cmd.failure?
        Rails.logger.error("Failed to execute trade decision for sell #{position[:symbol]}: #{execution_cmd.errors.full_messages.join(', ')}")
        stop_and_fail!("Failed to execute trade decision for sell #{position[:symbol]}")
      end

      execution = execution_cmd.trade_execution
      context.orders_placed << {
        id: execution.alpaca_order_id,
        symbol: position[:symbol],
        side: 'sell',
        qty: execution.filled_quantity || position[:qty],
        status: execution.status,
        submitted_at: execution.submitted_at
      }

      if execution.success?
        Rails.logger.info("Placed sell order to close position for #{position[:symbol]}: #{position[:qty]} shares")
      else
        handle_execution_failure(execution, position[:symbol], 'sell', position[:qty])
      end
    rescue StandardError => e
      Rails.logger.error("Failed to place sell order for #{position[:symbol]}: #{e.message}")
      stop_and_fail!("Failed to place sell order for #{position[:symbol]}: #{e.message}")
    end

    def place_buy_or_adjustment_order(target_position, current_position)
      current_value = current_position&.dig(:market_value) || BigDecimal('0')
      target_value = target_position.target_value

      # If current value equals target value (within a small tolerance), skip
      tolerance = BigDecimal('0.01') # $0.01 tolerance
      return if (current_value - target_value).abs <= tolerance

      side = target_value > current_value ? 'buy' : 'sell'
      notional_amount = (target_value - current_value).abs

      # Skip very small adjustments
      return if notional_amount < 1.0

      if dry_run?
        context.orders_placed << {
          symbol: target_position.symbol,
          side: side,
          status: 'planned',
          notional: notional_amount
        }
        return
      end

      # 1. Create decision
      quiver_trade_id = target_position.details[:quiver_trade_ids]&.first

      decision_cmd = AuditTrail::CreateTradeDecision.call(
        strategy_name: 'RebalanceToTarget',
        symbol: target_position.symbol,
        side: side,
        quantity: 1, # Placeholder for notional
        primary_quiver_trade_id: quiver_trade_id,
        rationale: {
          trigger_event: 'rebalance_adjustment',
          notional_amount: notional_amount.to_f,
          target_value: target_value.to_f,
          current_value: current_value.to_f,
          source_quiver_trade_ids: target_position.details[:quiver_trade_ids]
        }
      )

      if decision_cmd.failure?
        Rails.logger.error("Failed to create trade decision for #{side} #{target_position.symbol}: #{decision_cmd.errors.full_messages.join(', ')}")
        stop_and_fail!("Failed to create trade decision for #{side} #{target_position.symbol}")
      end

      # 2. Execute
      # I'll manually call alpaca for now or update ExecuteTradeDecision
      # Actually, I'll update ExecuteTradeDecision to support notional.

      execution_cmd = AuditTrail::ExecuteTradeDecision.call(
        trade_decision: decision_cmd.trade_decision,
        notional: notional_amount # I'll add this to ExecuteTradeDecision
      )

      if execution_cmd.failure?
        Rails.logger.error("Failed to execute trade decision for #{side} #{target_position.symbol}: #{execution_cmd.errors.full_messages.join(', ')}")
        stop_and_fail!("Failed to execute trade decision for #{side} #{target_position.symbol}")
      end

      execution = execution_cmd.trade_execution
      context.orders_placed << {
        id: execution.alpaca_order_id,
        symbol: target_position.symbol,
        side: side,
        status: execution.status,
        notional: notional_amount
      }

      return if execution.success?

      handle_execution_failure(execution, target_position.symbol, side, notional_amount)
    end

    def handle_execution_failure(execution, symbol, side, _amount)
      error_msg = execution.error_message || ''

      case error_msg
      when /insufficient buying power|insufficient funds/i
        BlockedAsset.block_asset(symbol: symbol, reason: 'insufficient_buying_power') if side == 'buy'
        Rails.logger.warn("Blocked #{symbol}: insufficient buying power")
      when /not fractionable/i
        BlockedAsset.block_asset(symbol: symbol, reason: 'not_fractionable')
        Rails.logger.warn("Blocked #{symbol}: not fractionable (will use whole shares if retried)")
      when /asset .+ is not active|not tradable/i
        BlockedAsset.block_asset(symbol: symbol, reason: 'asset_not_active')
        Rails.logger.warn("Blocked #{symbol}: asset not active/tradable")
      end
      # We don't stop_and_fail here because we want to continue with other trades
    end
  end
end
