# frozen_string_literal: true

# QuiverTrade represents raw congressional trading data fetched from the Quiver Quantitative API
# This model stores trading signals that will be used for our automated trading strategy.
class QuiverTrade < ApplicationRecord
  INSIDER_RELATIONSHIPS = [
    'CEO',
    'CFO',
    'COO',
    'Director',
    'Officer',
    '10% Owner',
    'Other'
  ].freeze

  before_validation :normalize_relationship

  validates :ticker, presence: true
  validates :transaction_date, presence: true
  validates :transaction_type, presence: true

  # Insider-specific fields
  validates :relationship, inclusion: { in: INSIDER_RELATIONSHIPS, allow_nil: true }

  # Scopes for common queries
  scope :for_ticker, ->(ticker) { where(ticker: ticker) }
  scope :purchases, -> { where(transaction_type: 'Purchase') }
  scope :sales, -> { where(transaction_type: 'Sale') }
  scope :between_dates, ->(start_date, end_date) { where(transaction_date: start_date..end_date) }
  scope :ordered_by_date, -> { order(:transaction_date) }
  scope :recent, ->(days = 45, date: Time.current) { where(transaction_date: (date - days.days)..date) }
  # Insider helper scopes
  scope :insiders, -> { where(trader_source: 'insider') }
  scope :c_suite, -> { where(relationship: %w[CEO CFO COO]) }
  scope :form4_trades, -> { where(trade_type: 'Form4') }

  private

  def normalize_relationship
    return if relationship.blank?

    normalized = relationship.to_s.strip.upcase

    self.relationship = if normalized.include?('CHIEF EXECUTIVE OFFICER') || normalized == 'CEO'
                          'CEO'
                        elsif normalized.include?('CHIEF FINANCIAL OFFICER') || normalized == 'CFO'
                          'CFO'
                        elsif normalized.include?('CHIEF OPERATING OFFICER') || normalized == 'COO'
                          'COO'
                        elsif normalized.include?('DIRECTOR')
                          'Director'
                        elsif normalized.include?('10%')
                          '10% Owner'
                        elsif normalized.include?('OFFICER') || normalized.include?('PRESIDENT')
                          'Officer'
                        else
                          relationship.to_s.strip
                        end
  end
end
