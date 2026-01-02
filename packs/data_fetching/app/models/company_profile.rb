# frozen_string_literal: true

# CompanyProfile
#
# Cached company profile / fundamentals for a ticker (sector, industry, identifiers, etc.).
# Primarily populated from Financial Modeling Prep (FMP).
class CompanyProfile < ApplicationRecord
  validates :ticker, presence: true, uniqueness: true
  validates :fetched_at, presence: true
  validates :source, presence: true

  scope :for_ticker, ->(ticker) { where(ticker: ticker.to_s.upcase) }
  scope :stale_before, ->(time) { where('fetched_at < ?', time) }
end
