# frozen_string_literal: true

module AuditTrail
  class DataIngestionRunRecord < ApplicationRecord
    self.table_name = 'data_ingestion_run_records'

    belongs_to :data_ingestion_run, class_name: 'AuditTrail::DataIngestionRun'
    belongs_to :record, polymorphic: true

    # Validations
    validates :operation, inclusion: { in: %w[created updated skipped] }

    # Scopes
    scope :created_records, -> { where(operation: 'created') }
    scope :updated_records, -> { where(operation: 'updated') }
    scope :skipped_records, -> { where(operation: 'skipped') }
  end
end
