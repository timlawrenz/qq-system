# frozen_string_literal: true

# AnalysePerformanceJob
#
# Background job that triggers the actual performance analysis calculations.
# It delegates the business logic to the AnalysePerformance command.
class AnalysePerformanceJob < ApplicationJob
  # Add a rescue block to handle any exceptions, update the model, and then re-raise
  # so the job is still marked as failed by the queueing system.
  rescue_from StandardError do |exception|
    analysis_id = arguments.first
    analysis = Analysis.find_by(id: analysis_id)

    if analysis
      analysis.update(results: { error: "Job failed: #{exception.message}" })
      analysis.mark_as_failed! if analysis.can_mark_as_failed?
    end

    # Re-raise the exception so the job is properly marked as failed
    raise exception
  end

  def perform(analysis_id)
    analysis = Analysis.find(analysis_id)
    analysis.start!

    # Call the business logic command
    result = AnalysePerformance.call!(analysis: analysis)

    if result.success?
      # Store results and mark as completed
      analysis.update!(results: result.results)
      analysis.complete!
    else
      # This part will now likely be skipped in favor of the command raising an exception
      Rails.logger.error("AnalysePerformance command failed: #{result.error}")
      analysis.update!(results: { error: result.error })
      analysis.mark_as_failed!
    end
  end
end
