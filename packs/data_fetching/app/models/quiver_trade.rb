# frozen_string_literal: true

# QuiverTrade represents raw congressional trading data fetched from the Quiver Quantitative API
# This model stores trading signals that will be used for our automated trading strategy.
class QuiverTrade < ApplicationRecord
  validates :ticker, presence: true
  validates :transaction_date, presence: true
  validates :transaction_type, presence: true

  # Scopes for common queries
  scope :for_ticker, ->(ticker) { where(ticker: ticker) }
  scope :purchases, -> { where(transaction_type: 'Purchase') }
  scope :sales, -> { where(transaction_type: 'Sale') }
  scope :between_dates, ->(start_date, end_date) { where(transaction_date: start_date..end_date) }
  scope :ordered_by_date, -> { order(:transaction_date) }
  scope :recent, ->(days = 45, date: Time.current) { where(transaction_date: (date - days.days)..date) }
end
