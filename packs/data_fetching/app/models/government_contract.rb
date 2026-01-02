# frozen_string_literal: true

# GovernmentContract
#
# Stores government contract award data from QuiverQuant.
# Each record represents an award event to a public company.
class GovernmentContract < ApplicationRecord
  validates :contract_id, presence: true, uniqueness: true
  validates :ticker, presence: true
  validates :award_date, presence: true
  validates :contract_value, presence: true, numericality: { greater_than: 0 }

  scope :recent, ->(days) { where('award_date >= ?', days.days.ago.to_date) }
  scope :by_agency, ->(agency) { where(agency: agency) }
  scope :minimum_value, ->(amount) { where('contract_value >= ?', amount) }
  scope :for_ticker, ->(ticker) { where(ticker: ticker) }
end
