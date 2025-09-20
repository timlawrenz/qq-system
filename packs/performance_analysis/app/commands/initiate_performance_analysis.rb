# frozen_string_literal: true

# InitiatePerformanceAnalysis Command
#
# This command provides the API interface for initiating performance analysis.
# It accepts algorithm_id and date range, then delegates to
# EnqueueAnalysePerformanceJob to create the analysis and enqueue the background job.
class InitiatePerformanceAnalysis < GLCommand::Callable
  requires algorithm_id: Integer,
           start_date: Date,
           end_date: Date
  returns :analysis

  validate :validate_algorithm_exists,
           :validate_date_range

  def call
    # Get the algorithm
    algorithm = Algorithm.find(context.algorithm_id)

    # Delegate to the existing command
    result = EnqueueAnalysePerformanceJob.call(
      algorithm: algorithm,
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

  def validate_algorithm_exists
    algorithm = Algorithm.find_by(id: context.algorithm_id)
    errors.add(:algorithm_id, 'not found') unless algorithm
  end

  def validate_date_range
    return unless context.start_date && context.end_date

    errors.add(:end_date, 'must be after start date') if context.end_date < context.start_date
  end
end
