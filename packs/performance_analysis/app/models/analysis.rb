# frozen_string_literal: true

class Analysis < ApplicationRecord
  belongs_to :algorithm

  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :status, presence: true

  state_machine :status, initial: :pending do
    event :start do
      transition pending: :running
    end

    event :complete do
      transition running: :completed
    end

    event :mark_as_failed do
      transition %i[pending running] => :failed
    end

    event :retry_analysis do
      transition failed: :pending
    end
  end

  validate :end_date_after_start_date

  private

  def end_date_after_start_date
    return unless start_date && end_date

    errors.add(:end_date, 'must be after start date') if end_date < start_date
  end
end
