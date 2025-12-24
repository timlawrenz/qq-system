# frozen_string_literal: true

module AuditTrail
  class DataIngestionRun < ApplicationRecord
    self.table_name = 'data_ingestion_runs'

    # Associations
    has_many :data_ingestion_run_records,
             class_name: 'AuditTrail::DataIngestionRunRecord',
             dependent: :destroy
    has_many :api_call_logs,
             class_name: 'AuditTrail::ApiCallLog',
             dependent: :destroy

    # Polymorphic associations for specific record types
    has_many :quiver_trades, through: :data_ingestion_run_records,
             source: :record, source_type: 'QuiverTrade'
    has_many :politician_profiles, through: :data_ingestion_run_records,
             source: :record, source_type: 'PoliticianProfile'

    # Validations
    validates :run_id, presence: true, uniqueness: true
    validates :task_name, presence: true
    validates :data_source, presence: true
    validates :status, inclusion: { in: %w[running completed failed] }
    validates :started_at, presence: true

    # State machine using acts_as_state_machine convention
    # No explicit state machine needed for simple status transitions

    # Scopes
    scope :recent, -> { where('started_at >= ?', 24.hours.ago).order(started_at: :desc) }
    scope :for_task, ->(task_name) { where(task_name: task_name) }
    scope :for_source, ->(data_source) { where(data_source: data_source) }
    scope :successful, -> { where(status: 'completed') }
    scope :failed_runs, -> { where(status: 'failed') }

    # Instance methods
    def duration_seconds
      return nil unless completed_at || failed_at

      ((completed_at || failed_at) - started_at).to_i
    end

    def success?
      status == 'completed'
    end
  end
end
