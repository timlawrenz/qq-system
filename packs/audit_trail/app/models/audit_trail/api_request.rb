# frozen_string_literal: true

module AuditTrail
  class ApiRequest < ApiPayload
    # Type-specific validations
    validate :payload_has_required_keys

    # Helper methods to access common request fields
    def endpoint
      payload['endpoint']
    end

    def http_method
      payload['method']
    end

    def params
      payload['params'] || payload['payload']
    end

    def headers
      payload['headers']
    end

    private

    def payload_has_required_keys
      return if payload.key?('endpoint')

      errors.add(:payload, 'must include endpoint')
    end
  end
end
