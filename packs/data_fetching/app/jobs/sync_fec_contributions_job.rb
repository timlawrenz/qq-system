# frozen_string_literal: true

class SyncFecContributionsJob < ApplicationJob
  queue_as :default

  def perform(cycle: 2024, force_refresh: false, politician_id: nil)
    Rails.logger.info "Starting FEC contributions sync for cycle #{cycle}..."

    result = SyncFecContributions.call(
      cycle: cycle,
      force_refresh: force_refresh,
      politician_id: politician_id
    )

    if result.success?
      stats = result.stats
      Rails.logger.info '✓ FEC sync successful'
      Rails.logger.info "  Politicians: #{stats[:politicians_processed]}"
      Rails.logger.info "  Created: #{stats[:contributions_created]}"
      Rails.logger.info "  Updated: #{stats[:contributions_updated]}"

      total = stats[:classified_amount] + stats[:unclassified_amount]
      classified_pct = total.positive? ? (stats[:classified_amount] / total * 100).round(1) : 0
      Rails.logger.info "  Classification rate: #{classified_pct}%"

      Rails.logger.warn '⚠️  Classification rate below 65% threshold!' if classified_pct < 65 && total > 10_000
    else
      Rails.logger.error "✗ FEC sync failed: #{result.error}"
      raise StandardError, result.error
    end
  end
end
