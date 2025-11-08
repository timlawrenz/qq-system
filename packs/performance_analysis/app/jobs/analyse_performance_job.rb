# frozen_string_literal: true

# AnalysePerformanceJob
#
# Background job that triggers the actual performance analysis calculations.
# It delegates the business logic to the AnalysePerformance command.
class AnalysePerformanceJob < ApplicationJob
  def perform(analysis_id)
    analysis = Analysis.find(analysis_id)
    analysis.start!

    begin
      result = AnalysePerformance.call!(analysis: analysis)
      analysis.update!(results: result.results)
      analysis.complete!
    rescue StandardError => e
      analysis.update!(results: { error: "Job failed: #{e.message}" })
      analysis.mark_as_failed! if analysis.can_mark_as_failed?
    end
  end
end
