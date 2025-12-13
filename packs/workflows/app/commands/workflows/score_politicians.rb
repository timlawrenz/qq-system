# frozen_string_literal: true

module Workflows
  # ScorePoliticians Command
  #
  # Scores politician profiles based on historical trading performance.
  # Only runs if profiles need updating (>1 week old or never scored).
  class ScorePoliticians < GLCommand::Callable
    allows :force_rescore

    returns :scored_count, :was_needed

    def call
      context.force_rescore ||= false

      if scoring_needed? || context.force_rescore
        Rails.logger.info('ScorePoliticians: Running politician scoring job')
        ScorePoliticiansJob.perform_now

        context.scored_count = PoliticianProfile.with_quality_score.count
        context.was_needed = true

        Rails.logger.info("ScorePoliticians: Scored #{context.scored_count} profiles")
      else
        context.scored_count = PoliticianProfile.with_quality_score.count
        context.was_needed = false

        Rails.logger.info(
          "ScorePoliticians: Already scored recently (#{context.scored_count} profiles)"
        )
      end
    rescue StandardError => e
      Rails.logger.error("ScorePoliticians: Failed: #{e.message}")
      stop_and_fail!(e)
    end

    private

    def scoring_needed?
      PoliticianProfile.exists?(['last_scored_at IS NULL OR last_scored_at < ?', 1.week.ago]) ||
        PoliticianProfile.none?
    end
  end
end
