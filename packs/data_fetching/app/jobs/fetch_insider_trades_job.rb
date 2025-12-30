# frozen_string_literal: true

# FetchInsiderTradesJob
#
# Background job that fetches recent corporate insider trades from QuiverQuant
# and upserts them into the quiver_trades table via the FetchInsiderTrades
# GLCommand. This is a thin wrapper so that we can schedule insider data
# refreshes via jobs OR cron + rake.
#
# Recommended Schedule (cron):
#   - 8:10 AM ET weekdays: FetchInsiderTradesJob.perform_now (60-day lookback)
#
# Responsibilities:
# 1. Call FetchInsiderTrades with sensible defaults
# 2. Provide structured logging around each run
# 3. Retry on transient failures with exponential backoff
#
# Usage:
#   FetchInsiderTradesJob.perform_now
#   FetchInsiderTradesJob.perform_now(start_date: 60.days.ago.to_date, end_date: Date.current, limit: 1000)
#   FetchInsiderTradesJob.perform_later
class FetchInsiderTradesJob < ApplicationJob
  queue_as :default

  # Retry configuration: 3 attempts with exponential backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # @param start_date [Date,nil]
  # @param end_date [Date,nil]
  # @param lookback_days [Integer,nil]
  # @param limit [Integer,nil]
  def perform(start_date: nil, end_date: nil, lookback_days: nil, limit: nil)
    Rails.logger.info('=' * 80)
    Rails.logger.info('FetchInsiderTradesJob: Starting insider data fetch')
    Rails.logger.info("  start_date: #{start_date || 'lookback-based'}")
    Rails.logger.info("  end_date: #{end_date || 'today'}")
    Rails.logger.info("  lookback_days: #{lookback_days || 60}")
    Rails.logger.info("  limit: #{limit || 1000}")
    Rails.logger.info('=' * 80)

    result = FetchInsiderTrades.call(
      start_date: start_date,
      end_date: end_date,
      lookback_days: lookback_days,
      limit: limit
    )

    if result.success?
      Rails.logger.info(
        "FetchInsiderTradesJob: SUCCESS - total=#{result.total_count}, new=#{result.new_count}, updated=#{result.updated_count}, errors=#{result.error_count}"
      )

      if result.error_count.positive? && result.respond_to?(:error_messages)
        Rails.logger.warn('FetchInsiderTradesJob: error messages (first 5):')
        Array(result.error_messages).first(5).each do |msg|
          Rails.logger.warn("  - #{msg}")
        end
      end
    else
      Rails.logger.error("FetchInsiderTradesJob: FAILED - #{result.full_error_message}")
      raise result.error || StandardError.new(result.full_error_message)
    end

    Rails.logger.info('=' * 80)
    Rails.logger.info('FetchInsiderTradesJob: Complete')
    Rails.logger.info('=' * 80)
  rescue StandardError => e
    Rails.logger.error("FetchInsiderTradesJob: Unexpected error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    raise
  end
end
