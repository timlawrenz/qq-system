# frozen_string_literal: true

# AnalysePerformanceJob
#
# Background job that triggers the actual performance analysis calculations.
# It delegates the business logic to the AnalysePerformance command.
class AnalysePerformanceJob < ApplicationJob
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
      Rails.logger.error("AnalysePerformance command failed: #{result.error}")
      analysis.mark_as_failed!
    end
  rescue StandardError => e
    Rails.logger.error("AnalysePerformanceJob failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    analysis = Analysis.find(analysis_id)
    analysis.mark_as_failed! if analysis.status != 'failed'
  end
end
