# frozen_string_literal: true

# AnalysePerformance Command
#
# This command creates an Analysis record with pending status and enqueues
# a background job to perform the actual performance analysis calculations.
class AnalysePerformance < GLCommand::Callable
  requires :algorithm_id, :start_date, :end_date
  returns :analysis

  validates :algorithm_id, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :validate_date_range
  validate :validate_algorithm_exists

  def call
    # Create Analysis record with pending status
    analysis = Analysis.create!(
      algorithm_id: context.algorithm_id,
      start_date: parse_date(context.start_date),
      end_date: parse_date(context.end_date),
      status: 'pending'
    )

    # Enqueue background job to perform the analysis
    AnalysePerformanceJob.perform_later(analysis.id)

    context.analysis = analysis
  end

  private

  def validate_date_range
    return unless context.start_date && context.end_date

    start_date = parse_date(context.start_date)
    end_date = parse_date(context.end_date)

    return unless start_date && end_date

    errors.add(:end_date, 'must be after start date') if end_date < start_date
  end

  def validate_algorithm_exists
    return unless context.algorithm_id

    return if Algorithm.exists?(context.algorithm_id)

    errors.add(:algorithm_id, 'must reference an existing algorithm')
  end

  def parse_date(date_input)
    case date_input
    when Date, Time, DateTime
      date_input.to_date
    when String
      Date.parse(date_input)
    else
      date_input
    end
  rescue ArgumentError
    nil
  end
end
