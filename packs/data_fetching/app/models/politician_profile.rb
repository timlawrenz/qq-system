# frozen_string_literal: true

# rubocop:disable Naming/PredicatePrefix

class PoliticianProfile < ApplicationRecord
  # Associations
  has_many :committee_memberships, dependent: :destroy
  has_many :committees, through: :committee_memberships

  # The relationship to QuiverTrade is through trader_name matching, not a foreign key
  # trades = QuiverTrade.where(trader_name: politician.name, trader_source: 'congress')

  # Validations
  validates :name, presence: true
  validates :bioguide_id, uniqueness: true, allow_nil: true
  validates :quality_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }, allow_nil: true
  validates :total_trades, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :winning_trades, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :average_return, numericality: true, allow_nil: true

  # Scopes
  scope :with_quality_score, -> { where.not(quality_score: nil) }
  scope :high_quality, ->(min_score = 7.0) { where(quality_score: min_score..) }
  scope :recently_scored, -> { where(last_scored_at: 1.month.ago..) }

  # Instance methods
  def trades
    QuiverTrade.where(trader_name: name, trader_source: 'congress')
  end

  def recent_trades(days = 45)
    trades.where(transaction_date: days.days.ago..)
  end

  def win_rate
    return nil if total_trades.nil? || total_trades.zero?

    (winning_trades.to_f / total_trades * 100).round(2)
  end

  def needs_scoring?
    last_scored_at.nil? || last_scored_at < 1.month.ago
  end

  def has_committee_oversight?(industry_names)
    return false if committees.empty?

    industry_ids = Industry.where(name: industry_names).pluck(:id)
    committees.joins(:industries).exists?(industries: { id: industry_ids })
  end
end
# rubocop:enable Naming/PredicatePrefix
