# frozen_string_literal: true

# AlpacaOrder represents orders placed with the Alpaca API for our trading account.
# This model logs every order for tracking and reconciliation purposes.
class AlpacaOrder < ApplicationRecord
  belongs_to :quiver_trade, optional: true

  validates :alpaca_order_id, presence: true, uniqueness: true
  validates :symbol, presence: true
  validates :side, presence: true, inclusion: { in: %w[buy sell] }
  validates :status, presence: true

  # Scopes for common queries
  scope :for_symbol, ->(symbol) { where(symbol: symbol) }
  scope :buys, -> { where(side: 'buy') }
  scope :sells, -> { where(side: 'sell') }
  scope :by_status, ->(status) { where(status: status) }
  scope :filled, -> { where.not(filled_at: nil) }
  scope :pending, -> { where(filled_at: nil) }
  scope :ordered_by_submitted, -> { order(:submitted_at) }
end
