# frozen_string_literal: true

module AuditTrail
  class TradeExecution < ApplicationRecord
    self.table_name = 'trade_executions'

    # Associations
    belongs_to :trade_decision, class_name: 'AuditTrail::TradeDecision'
    belongs_to :api_request_payload, class_name: 'AuditTrail::ApiRequest',
               foreign_key: 'api_request_payload_id', optional: true
    belongs_to :api_response_payload, class_name: 'AuditTrail::ApiResponse',
               foreign_key: 'api_response_payload_id', optional: true

    # Validations
    validates :execution_id, presence: true, uniqueness: true
    validates :status, inclusion: {
      in: %w[submitted accepted filled rejected cancelled partial_fill]
    }
    validates :attempt_number, numericality: { greater_than: 0 }

    # Scopes
    scope :successful, -> { where(status: 'filled') }
    scope :failed, -> { where(status: 'rejected') }
    scope :pending, -> { where(status: %w[submitted accepted]) }
    scope :recent, -> { where('created_at >= ?', 24.hours.ago).order(created_at: :desc) }

    # Instance methods
    def success?
      status == 'filled'
    end

    def failure?
      status == 'rejected'
    end

    def pending?
      %w[submitted accepted].include?(status)
    end

    # Access API payloads
    def request_payload
      api_request_payload&.payload || {}
    end

    def response_payload
      api_response_payload&.payload || {}
    end

    # Convenience accessors
    def request_endpoint
      api_request_payload&.endpoint
    end

    def response_status_code
      api_response_payload&.status_code
    end

    def api_success?
      api_response_payload&.success?
    end
  end
end
