# frozen_string_literal: true

# InitiatePerformanceAnalysis Command
#
# This command provides the API interface for initiating performance analysis.
# It accepts algorithm object and date range, then delegates to
# EnqueueAnalysePerformanceJob to create the analysis and enqueue the background job.
class InitiatePerformanceAnalysis < GLCommand::Callable
  requires algorithm: Algorithm,
           start_date: Date,
           end_date: Date
  returns :analysis

  validate :validate_date_range

  def call
    # Delegate to the existing command
    result = EnqueueAnalysePerformanceJob.call(
      algorithm: context.algorithm,
      start_date: context.start_date,
      end_date: context.end_date
    )

    if result.success?
      context.analysis = result.analysis
    else
      stop_and_fail!(result.errors.full_messages.join(', '))
    end
  end

  private

  def validate_date_range
    return unless context.start_date && context.end_date

    errors.add(:end_date, 'must be after start date') if context.end_date < context.start_date
  end
end
