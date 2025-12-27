# frozen_string_literal: true

module AuditTrail
  # ExecuteTradeDecision Command
  #
  # Synchronously executes a trade decision via the Alpaca API and logs
  # the interaction for the audit trail.
  #
  # Responsibilities:
  # 1. Validate that the decision is in "pending" state.
  # 2. Store the API request payload before execution.
  # 3. Call Alpaca API to place the order.
  # 4. Store the API response payload.
  # 5. Create a TradeExecution record linking everything together.
  # 6. Update the TradeDecision status based on the result.
  class ExecuteTradeDecision < GLCommand::Callable
    requires :trade_decision
    allows :notional, :close_position
    returns :trade_execution

    def call
      validate_decision!

      # 1. Build and store request payload
      api_request = store_request

      # 2. Execute trade via Alpaca
      response = execute_alpaca_order

      # 3. Store response payload
      api_response = store_response(response)

      # 4. Create execution record
      execution = create_execution(api_request, api_response, response)

      # 5. Update decision status
      update_decision(execution)

      context.trade_execution = execution

      if execution.success?
        Rails.logger.info("✅ Trade executed: #{execution.execution_id} (Alpaca ID: #{execution.alpaca_order_id})")
      elsif execution.pending?
        Rails.logger.info("⏳ Trade submitted: #{execution.execution_id} (Alpaca ID: #{execution.alpaca_order_id}, status: #{execution.status})")
      else
        Rails.logger.warn("❌ Trade failed: #{execution.error_message}")
      end

      context
    rescue StandardError => e
      # If something goes wrong in the command logic itself (not the API call),
      # we still want to fail the decision if possible.
      if context.trade_decision&.pending?
        context.trade_decision.fail!
        context.trade_decision.update!(failed_at: Time.current)
      end
      stop_and_fail!(e.message)
    end

    private

    def validate_decision!
      decision = context.trade_decision
      return if decision.status == 'pending'

      stop_and_fail!("Decision #{decision.decision_id} is not pending (status: #{decision.status})")
    end

    def store_request
      decision = context.trade_decision
      payload = {
        symbol: decision.symbol,
        side: decision.side,
        type: decision.order_type,
        time_in_force: 'day'
      }

      if context.notional.present?
        payload[:notional] = context.notional
      else
        payload[:qty] = decision.quantity
      end

      request_data = {
        endpoint: '/v2/orders',
        method: 'POST',
        payload: payload
      }

      ApiRequest.create!(
        source: 'alpaca',
        captured_at: Time.current,
        payload: request_data
      )
    end

    def execute_alpaca_order
      decision = context.trade_decision
      alpaca_service = AlpacaService.new

      # Use close_position for liquidations (sells with no target position)
      if context.close_position && decision.side == 'sell'
        alpaca_service.close_position(symbol: decision.symbol)
      elsif context.notional.present?
        # Try notional order first if notional is specified
        begin
          alpaca_service.place_order(
            symbol: decision.symbol,
            side: decision.side,
            qty: nil,
            notional: context.notional
          )
        rescue StandardError => e
          # If asset is not fractionable, fallback to whole shares
          raise e unless /not fractionable/i.match?(e.message)

          Rails.logger.warn("Asset #{decision.symbol} not fractionable, falling back to whole shares")
          qty = calculate_whole_shares(decision.symbol, context.notional, decision.side)

          if qty&.positive?
            alpaca_service.place_order(
              symbol: decision.symbol,
              side: decision.side,
              qty: qty,
              notional: nil
            )
          else
            raise StandardError,
                  "Cannot calculate whole shares for #{decision.symbol} with notional #{context.notional}"
          end
        end
      else
        # Use quantity-based order
        alpaca_service.place_order(
          symbol: decision.symbol,
          side: decision.side,
          qty: decision.quantity,
          notional: nil
        )
      end
    rescue StandardError => e
      # Return error as pseudo-response hash for logging
      {
        'status' => 'error',
        'message' => e.message,
        'http_status' => 500
      }
    end

    def calculate_whole_shares(symbol, notional_amount, _side)
      # Get current price from Alpaca
      alpaca_service = AlpacaService.new
      latest_trade = alpaca_service.latest_trade(symbol)
      price = latest_trade&.dig(:price)

      unless price&.positive?
        Rails.logger.warn("No price data available for #{symbol}, cannot calculate whole shares - will block asset")
        # Block this asset as it has no market data
        BlockedAsset.block_asset(symbol: symbol, reason: 'no_price_data')
        return nil
      end

      # Calculate whole shares
      shares = (notional_amount.to_f / price).floor

      if shares.zero?
        Rails.logger.warn("Notional amount #{notional_amount} too small to buy even 1 share of #{symbol} at #{price}")
        return nil
      end

      Rails.logger.info("Calculated #{shares} whole shares for #{symbol} at $#{price} (notional: $#{notional_amount})")
      shares
    rescue StandardError => e
      Rails.logger.error("Failed to calculate whole shares for #{symbol}: #{e.message}")
      nil
    end

    def store_response(response)
      ApiResponse.create!(
        source: 'alpaca',
        captured_at: Time.current,
        payload: response
      )
    end

    def create_execution(api_request, api_response, response)
      status = map_alpaca_status(response['status'] || response[:status])

      TradeExecution.create!(
        trade_decision: context.trade_decision,
        execution_id: SecureRandom.uuid,
        attempt_number: 1, # No retries
        status: status,
        api_request_payload: api_request,
        api_response_payload: api_response,
        alpaca_order_id: response['id'] || response[:id],
        http_status_code: response['http_status'] || 200,
        error_message: response['message'] || response[:message],
        filled_quantity: response['filled_qty'] || response[:qty],
        filled_avg_price: response['filled_avg_price'],
        submitted_at: response['submitted_at'] || Time.current,
        filled_at: response['status'] == 'filled' ? Time.current : nil,
        rejected_at: status == 'rejected' ? Time.current : nil
      )
    end

    def map_alpaca_status(alpaca_status)
      case alpaca_status&.to_s&.downcase
      when 'new', 'pending_new', 'accepted' then 'submitted'
      when 'filled' then 'filled'
      when 'rejected', 'canceled', 'error' then 'rejected'
      when 'partially_filled' then 'partial_fill'
      else 'rejected' # Default to rejected for safety if unknown
      end
    end

    def update_decision(execution)
      decision = context.trade_decision
      if execution.success?
        decision.execute!
        decision.update!(executed_at: Time.current)
      else
        decision.fail!
        decision.update!(failed_at: Time.current)
      end
    end
  end
end
