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
    allows :notional
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
      unless decision.status == 'pending'
        stop_and_fail!("Decision #{decision.decision_id} is not pending (status: #{decision.status})")
      end
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
      
      alpaca_service.place_order(
        symbol: decision.symbol,
        side: decision.side,
        qty: context.notional.present? ? nil : decision.quantity,
        notional: context.notional
      )
    rescue StandardError => e
      # Return error as pseudo-response hash for logging
      {
        'status' => 'error',
        'message' => e.message,
        'http_status' => 500
      }
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
