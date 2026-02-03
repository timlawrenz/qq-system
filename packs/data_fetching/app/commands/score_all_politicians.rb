# frozen_string_literal: true

# ScoreAllPoliticians Command
#
# Scores all politician profiles based on their trading activity and performance.
# Also ensures that profiles exist for all traders found in the Quiver trades data.
#
class ScoreAllPoliticians < GLCommand::Callable
  returns :profiles_count, :scored_count, :created_count

  def call
    ensure_profiles_exist
    score_profiles
  end

  private

  def ensure_profiles_exist
    trader_names = QuiverTrade.where(trader_source: 'congress')
                              .distinct
                              .pluck(:trader_name)
                              .compact

    existing_names = PoliticianProfile.pluck(:name)
    missing_names = trader_names - existing_names

    Rails.logger.info "ScoreAllPoliticians: Creating #{missing_names.count} missing politician profiles..."
    context.created_count = 0

    missing_names.each do |name|
      PoliticianProfile.find_or_create_by!(name: name) do |profile|
        profile.quality_score = 5.0
        profile.last_scored_at = Time.current
        context.created_count += 1
      end
    end
  end

  def score_profiles
    profiles = PoliticianProfile.all
    context.profiles_count = profiles.count
    context.scored_count = 0

    Rails.logger.info "ScoreAllPoliticians: Scoring #{profiles.count} politicians..."

    profiles.find_each do |profile|
      scorer = PoliticianScorer.new(profile)
      scorer.call
      context.scored_count += 1
    rescue StandardError => e
      Rails.logger.error "ScoreAllPoliticians: Failed to score #{profile.name}: #{e.message}"
    end
  end
end
