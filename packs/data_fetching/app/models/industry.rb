# frozen_string_literal: true

class Industry < ApplicationRecord
  # Associations
  has_many :committee_industry_mappings, dependent: :destroy
  has_many :committees, through: :committee_industry_mappings

  # Validations
  validates :name, presence: true, uniqueness: true

  # Scopes
  scope :by_sector, ->(sector) { where(sector: sector) }
  scope :with_committee_oversight, -> { joins(:committees).distinct }

  # Instance methods
  def self.classify_stock(ticker_or_company_name)
    # Simple keyword-based classification
    # This will be enhanced with more sophisticated logic later
    text = ticker_or_company_name.to_s.downcase

    industries = []

    # Technology
    industries << find_by(name: 'Technology') if text.match?(/tech|software|cloud|cyber|data|ai|chip|semi/)
    industries << find_by(name: 'Semiconductors') if text.match?(/nvidia|amd|intel|micro|chip|semi/)

    # Healthcare
    industries << find_by(name: 'Healthcare') if text.match?(/health|pharma|bio|medic|drug/)

    # Energy
    industries << find_by(name: 'Energy') if text.match?(/energy|oil|gas|solar|wind|electric/)

    # Finance
    industries << find_by(name: 'Financial Services') if text.match?(/bank|financial|invest|insurance/)

    # Defense
    industries << find_by(name: 'Defense') if text.match?(/defense|aerospace|lockheed|boeing|raytheon/)

    industries.compact.presence || [find_by(name: 'Other')]
  end
end
