# frozen_string_literal: true

# EnqueueAnalysePerformanceJob Command
#
# This command creates an Analysis record with pending status and enqueues
# a background job to perform the actual performance analysis calculations.
class EnqueueAnalysePerformanceJob < GLCommand::Callable
  requires algorithm: Algorithm,
           start_date: Date,
           end_date: Date
  returns :analysis

  validate :validate_date_range

  def call
    # Create Analysis record with pending status
    analysis = Analysis.create!(
      algorithm: context.algorithm,
      start_date: context.start_date,
      end_date: context.end_date,
      status: 'pending'
    )

    # Enqueue background job to perform the analysis
    AnalysePerformanceJob.perform_later(analysis.id)

    context.analysis = analysis
  end

  private

  def validate_date_range
    return unless context.start_date && context.end_date

    errors.add(:end_date, 'must be after start date') if context.end_date < context.start_date
  end
end
