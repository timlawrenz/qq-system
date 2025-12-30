# frozen_string_literal: true

module AuditTrail
  class ApiPayload < ApplicationRecord
    self.table_name = 'api_payloads'

    # STI types: ApiRequest, ApiResponse
    validates :type, presence: true, inclusion: {
      in: %w[AuditTrail::ApiRequest AuditTrail::ApiResponse]
    }
    validates :payload, presence: true
    validates :source, presence: true, inclusion: {
      in: %w[alpaca quiverquant propublica]
    }
    validates :captured_at, presence: true

    # Scopes
    scope :recent, -> { where(captured_at: 24.hours.ago..) }
    scope :for_source, ->(source) { where(source: source) }
    scope :older_than, ->(date) { where(captured_at: ...date) }

    # Class method for bulk cleanup
    def self.purge_old_payloads(before_date:)
      where(captured_at: ...before_date).delete_all
    end
  end
end
