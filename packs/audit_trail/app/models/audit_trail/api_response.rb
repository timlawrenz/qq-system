# frozen_string_literal: true

module AuditTrail
  class ApiResponse < ApiPayload
    # Helper methods to access common response fields
    def status_code
      payload['status_code'] || payload['http_status']
    end

    def success?
      status_code&.to_i&.between?(200, 299)
    end

    def error?
      status_code&.to_i&.>=(400)
    end

    def error_message
      payload['error'] || payload['message'] || payload['detail']
    end

    def body
      payload['body'] || payload
    end

    # Alpaca-specific helpers
    def order_id
      payload['id']
    end

    def filled_qty
      payload['filled_qty']
    end

    def filled_avg_price
      payload['filled_avg_price']
    end
  end
end
