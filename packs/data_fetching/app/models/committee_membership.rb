# frozen_string_literal: true

class CommitteeMembership < ApplicationRecord
  # Associations
  belongs_to :politician_profile
  belongs_to :committee

  # Validations
  validates :politician_profile_id, uniqueness: { scope: :committee_id }
  validate :end_date_after_start_date

  # Scopes
  scope :active, -> { where(end_date: nil).or(where(end_date: Date.current..)) }
  scope :historical, -> { where(end_date: ...Date.current) }
  scope :on_date, lambda { |date|
    where(start_date: ..date)
      .where('end_date IS NULL OR end_date >= ?', date)
  }

  # Instance methods
  def active?
    end_date.nil? || end_date >= Date.current
  end

  private

  def end_date_after_start_date
    return if end_date.nil? || start_date.nil?

    errors.add(:end_date, 'must be after start date') if end_date < start_date
  end
end
