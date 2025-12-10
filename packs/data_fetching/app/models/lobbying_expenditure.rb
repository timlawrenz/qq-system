# frozen_string_literal: true

# LobbyingExpenditure
#
# Stores corporate lobbying disclosure data from Quiver Quantitative API.
# Each record represents a single lobbying firm's (registrant) disclosure
# for a specific company (ticker) in a specific quarter.
#
# A company may use multiple lobbying firms per quarter, so the unique
# constraint is ticker + quarter + registrant.
#
# Example:
#   GOOGL in Q4 2025 may have:
#   - THE MADISON GROUP: $45,000
#   - FEDERAL STREET STRATEGIES: $30,000
#   Total Q4 2025 lobbying: $75,000
#
class LobbyingExpenditure < ApplicationRecord
  # Validations
  validates :ticker, presence: true
  validates :quarter, presence: true, format: { with: /\AQ[1-4] \d{4}\z/, message: 'must be in format "Q1 2025"' }
  validates :date, presence: true
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :registrant, presence: true
  
  # Scopes for common queries
  scope :for_ticker, ->(ticker) { where(ticker: ticker) }
  scope :for_quarter, ->(quarter) { where(quarter: quarter) }
  scope :for_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :recent, -> { order(date: :desc) }
  scope :by_amount, -> { order(amount: :desc) }
  
  # Get quarterly total lobbying spend for each ticker
  # Returns hash: { 'GOOGL' => 305000.0, 'AAPL' => 150000.0, ... }
  #
  # @param quarter [String] Quarter string like "Q4 2025"
  # @return [Hash<String, BigDecimal>] Ticker to total amount mapping
  def self.quarterly_totals(quarter)
    where(quarter: quarter)
      .group(:ticker)
      .sum(:amount)
  end
  
  # Get quarterly total for a specific ticker
  # Aggregates across all registrants (lobbying firms)
  #
  # @param ticker [String] Stock ticker symbol
  # @param quarter [String] Quarter string like "Q4 2025"
  # @return [BigDecimal] Total lobbying spend
  def self.quarterly_total_for_ticker(ticker, quarter)
    where(ticker: ticker, quarter: quarter).sum(:amount)
  end
  
  # Get top lobbying spenders for a quarter
  #
  # @param quarter [String] Quarter string like "Q4 2025"
  # @param limit [Integer] Number of top spenders to return
  # @return [Array<Array>] Array of [ticker, total_amount] pairs
  def self.top_spenders(quarter, limit: 10)
    quarterly_totals(quarter)
      .sort_by { |_ticker, amount| -amount }
      .first(limit)
  end
  
  # Get all quarters with data for a ticker
  #
  # @param ticker [String] Stock ticker symbol
  # @return [Array<String>] Sorted array of quarter strings
  def self.quarters_for_ticker(ticker)
    where(ticker: ticker)
      .distinct
      .pluck(:quarter)
      .sort
  end
  
  # Get lobbying trend for a ticker (quarterly totals over time)
  #
  # @param ticker [String] Stock ticker symbol
  # @return [Hash<String, BigDecimal>] Quarter to amount mapping, sorted
  def self.trend_for_ticker(ticker)
    where(ticker: ticker)
      .group(:quarter)
      .sum(:amount)
      .sort_by { |q, _| q }
      .to_h
  end
end
