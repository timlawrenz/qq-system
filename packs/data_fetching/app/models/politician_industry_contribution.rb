# frozen_string_literal: true

class PoliticianIndustryContribution < ApplicationRecord
  belongs_to :politician_profile
  belongs_to :industry

  scope :current_cycle, -> { where(cycle: 2024) }
  scope :significant, -> { where(total_amount: 10_000..) }

  validates :cycle, presence: true
  validates :total_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :contribution_count, numericality: { greater_than_or_equal_to: 0 }
  validates :employer_count, numericality: { greater_than_or_equal_to: 0 }

  def influence_score
    return 0 if total_amount.zero?

    base = Math.log10(total_amount + 1) * Math.log10(contribution_count + 1)
    max_possible = Math.log10(5_000_000) * Math.log10(1000)

    [(base / max_possible) * 10, 10].min.round(2)
  end

  def weight_multiplier
    1.0 + (influence_score / 10.0)
  end
end
