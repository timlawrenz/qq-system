# frozen_string_literal: true

module AuditTrail
  class ApiCallLog < ApplicationRecord
    self.table_name = 'api_call_logs'

    belongs_to :data_ingestion_run, class_name: 'AuditTrail::DataIngestionRun'
    belongs_to :api_request_payload, class_name: 'AuditTrail::ApiRequest',
               foreign_key: 'api_request_payload_id', optional: true
    belongs_to :api_response_payload, class_name: 'AuditTrail::ApiResponse',
               foreign_key: 'api_response_payload_id', optional: true

    validates :endpoint, presence: true

    # Scopes
    scope :successful, -> { where('http_status_code >= 200 AND http_status_code < 300') }
    scope :failed, -> { where('http_status_code >= 400') }

    def success?
      http_status_code&.between?(200, 299)
    end
  end
end
