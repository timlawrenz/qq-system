# frozen_string_literal: true

# rubocop:disable Rails/UniqueValidationWithoutIndex

class CommitteeIndustryMapping < ApplicationRecord
  # Associations
  belongs_to :committee
  belongs_to :industry

  # Validations
  validates :committee_id, uniqueness: { scope: :industry_id }
end
# rubocop:enable Rails/UniqueValidationWithoutIndex
