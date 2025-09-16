# frozen_string_literal: true

# HistoricalBar represents cached market data from external APIs (e.g., Alpaca)
# This model serves as a local database cache to prevent redundant API calls
# for historical market data.
class HistoricalBar < ApplicationRecord
  validates :symbol, presence: true
  validates :timestamp, presence: true
  validates :open, presence: true, numericality: { greater_than: 0 }
  validates :high, presence: true, numericality: { greater_than: 0 }
  validates :low, presence: true, numericality: { greater_than: 0 }
  validates :close, presence: true, numericality: { greater_than: 0 }
  validates :volume, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Ensure high >= low for price validation
  validate :high_greater_than_or_equal_to_low
  validate :open_within_high_low_range
  validate :close_within_high_low_range

  # Scopes for common queries
  scope :for_symbol, ->(symbol) { where(symbol: symbol) }
  scope :between_dates, ->(start_date, end_date) { where(timestamp: start_date..end_date) }
  scope :ordered_by_timestamp, -> { order(:timestamp) }

  private

  def high_greater_than_or_equal_to_low
    return unless high && low

    errors.add(:high, 'must be greater than or equal to low') if high < low
  end

  def open_within_high_low_range
    return unless open && high && low

    errors.add(:open, 'must be between low and high') unless open.between?(low, high)
  end

  def close_within_high_low_range
    return unless close && high && low

    errors.add(:close, 'must be between low and high') unless close.between?(low, high)
  end
end
