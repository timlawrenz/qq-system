# frozen_string_literal: true

module AuditTrail
  class TradeDecision < ApplicationRecord
    self.table_name = 'trade_decisions'

    # Associations
    has_many :trade_executions,
             class_name: 'AuditTrail::TradeExecution',
             dependent: :destroy
    belongs_to :primary_quiver_trade, class_name: 'QuiverTrade', optional: true
    belongs_to :primary_ingestion_run, class_name: 'AuditTrail::DataIngestionRun', optional: true

    # Validations
    validates :decision_id, presence: true, uniqueness: true
    validates :strategy_name, presence: true
    validates :symbol, presence: true, format: { with: /\A[A-Z]{1,5}\z/ }
    validates :side, inclusion: { in: %w[buy sell] }
    validates :quantity, numericality: { greater_than: 0 }
    validates :order_type, inclusion: { in: %w[market limit] }
    validates :status, inclusion: { in: %w[pending executed failed cancelled] }
    validates :decision_rationale, presence: true

    # State machine (using AASM)
    include AASM

    aasm column: :status do
      state :pending, initial: true
      state :executed
      state :failed
      state :cancelled

      event :execute do
        transitions from: :pending, to: :executed
      end

      event :fail do
        transitions from: :pending, to: :failed
      end

      event :cancel do
        transitions from: :pending, to: :cancelled
      end
    end

    # Scopes
    scope :pending_decisions, -> { where(status: 'pending') }
    scope :executed_decisions, -> { where(status: 'executed') }
    scope :failed_decisions, -> { where(status: 'failed') }
    scope :for_symbol, ->(symbol) { where(symbol: symbol.upcase) }
    scope :for_strategy, ->(strategy) { where(strategy_name: strategy) }
    scope :recent, -> { where('created_at >= ?', 24.hours.ago).order(created_at: :desc) }
    scope :by_signal_strength, -> { order("(decision_rationale->>'signal_strength')::numeric DESC") }

    # Instance methods
    def signal_strength
      decision_rationale['signal_strength']&.to_f
    end

    def confidence_score
      decision_rationale['confidence_score']&.to_f
    end

    def source_quiver_trade_ids
      decision_rationale.dig('source_data', 'quiver_trade_ids') || []
    end

    def trigger_event
      decision_rationale['trigger_event']
    end

    def market_price_at_decision
      decision_rationale.dig('market_context', 'current_price')&.to_f
    end

    def buying_power_at_decision
      decision_rationale.dig('portfolio_context', 'buying_power')&.to_f
    end

    # Latest execution (for error messages)
    def latest_execution
      trade_executions.order(created_at: :desc).first
    end

    def failure_reason
      latest_execution&.error_message
    end
  end
end
