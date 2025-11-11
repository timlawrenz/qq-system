# frozen_string_literal: true

class Committee < ApplicationRecord
  # Associations
  has_many :committee_memberships, dependent: :destroy
  has_many :politician_profiles, through: :committee_memberships
  has_many :committee_industry_mappings, dependent: :destroy
  has_many :industries, through: :committee_industry_mappings

  # Validations
  validates :code, presence: true, uniqueness: true
  validates :name, presence: true
  validates :chamber, inclusion: { in: %w[house senate joint] }, allow_nil: true

  # Scopes
  scope :house_committees, -> { where(chamber: 'house') }
  scope :senate_committees, -> { where(chamber: 'senate') }
  scope :with_industry_oversight, lambda { |industry_name|
    joins(:industries).where(industries: { name: industry_name })
  }

  # Instance methods
  def has_oversight_of?(industry_names)
    industry_names = Array(industry_names)
    industries.exists?(name: industry_names)
  end

  def display_name
    chamber_prefix = case chamber
                     when 'house' then 'House'
                     when 'senate' then 'Senate'
                     when 'joint' then 'Joint'
                     else ''
                     end

    "#{chamber_prefix} #{name}".strip
  end
end
