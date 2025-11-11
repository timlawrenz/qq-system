# frozen_string_literal: true

# Background job to score all politicians monthly
class ScorePoliticiansJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info '=' * 80
    Rails.logger.info 'ScorePoliticiansJob: Starting politician scoring'
    Rails.logger.info '=' * 80

    # First, ensure we have politician profiles for all traders
    create_missing_profiles

    # Then score all profiles
    score_all_profiles

    Rails.logger.info '=' * 80
    Rails.logger.info 'ScorePoliticiansJob: Complete'
    Rails.logger.info "  Total profiles: #{PoliticianProfile.count}"
    Rails.logger.info "  Scored profiles: #{PoliticianProfile.with_quality_score.count}"
    Rails.logger.info '=' * 80
  end

  private

  def create_missing_profiles
    trader_names = QuiverTrade.where(trader_source: 'congress')
                              .distinct
                              .pluck(:trader_name)
                              .compact

    existing_names = PoliticianProfile.pluck(:name)
    missing_names = trader_names - existing_names

    Rails.logger.info "  Creating #{missing_names.count} missing politician profiles..."

    missing_names.each do |name|
      PoliticianProfile.find_or_create_by!(name: name) do |profile|
        profile.quality_score = 5.0
        profile.last_scored_at = Time.current
      end
    end
  end

  def score_all_profiles
    profiles = PoliticianProfile.all

    Rails.logger.info "  Scoring #{profiles.count} politicians..."

    profiles.find_each do |profile|
      scorer = PoliticianScorer.new(profile)
      score = scorer.call

      Rails.logger.debug { "    #{profile.name}: #{score}" }
    rescue StandardError => e
      Rails.logger.error "    Failed to score #{profile.name}: #{e.message}"
    end
  end
end
