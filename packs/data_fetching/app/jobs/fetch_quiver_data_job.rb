# frozen_string_literal: true

# FetchQuiverDataJob
#
# Background job that fetches fresh congressional trading data from QuiverQuant API.
# This job should run daily before the trading strategy execution job.
#
# Recommended Schedule:
#   - 8:00 AM ET weekdays: Fetch fresh data
#   - 9:45 AM ET weekdays: ExecuteSimpleStrategyJob uses that data
#
# Responsibilities:
# 1. Call FetchQuiverData command with appropriate date range
# 2. Handle success/failure with clear logging
# 3. Retry on failure with exponential backoff
# 4. Alert on high error rates
#
# Usage:
#   FetchQuiverDataJob.perform_now
#   FetchQuiverDataJob.perform_later
#   FetchQuiverDataJob.perform_now(start_date: 30.days.ago.to_date, ticker: 'AAPL')
class FetchQuiverDataJob < ApplicationJob
  queue_as :default

  # Retry configuration: 3 attempts with exponential backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(start_date: nil, end_date: nil, ticker: nil)
    Rails.logger.info('=' * 80)
    Rails.logger.info('FetchQuiverDataJob: Starting data fetch')
    Rails.logger.info("  start_date: #{start_date || '60 days ago'}")
    Rails.logger.info("  end_date: #{end_date || 'today'}")
    Rails.logger.info("  ticker: #{ticker || 'all'}")
    Rails.logger.info('=' * 80)

    # Call the command
    result = FetchQuiverData.call(
      start_date: start_date,
      end_date: end_date,
      ticker: ticker
    )

    # Handle result
    if result.success?
      Rails.logger.info(
        'FetchQuiverDataJob: SUCCESS - ' \
        "Fetched #{result.trades_count} trades " \
        "(#{result.new_trades_count} new, #{result.updated_trades_count} updated)"
      )

      # Alert if high error rate (>10%)
      if result.error_count.positive? && result.trades_count.positive?
        error_rate = (result.error_count.to_f / result.trades_count * 100).round(1)
        if error_rate > 10.0
          Rails.logger.error(
            'FetchQuiverDataJob: HIGH ERROR RATE - ' \
            "#{result.error_count} trades failed to save (#{error_rate}% error rate)"
          )
        else
          Rails.logger.warn(
            "FetchQuiverDataJob: #{result.error_count} trades failed to save (#{error_rate}% error rate)"
          )
        end
      end
    else
      Rails.logger.error("FetchQuiverDataJob: FAILED - #{result.error}")
      raise result.error # Re-raise to mark job as failed for retry
    end

    Rails.logger.info('=' * 80)
    Rails.logger.info('FetchQuiverDataJob: Complete')
    Rails.logger.info('=' * 80)
  rescue StandardError => e
    Rails.logger.error("FetchQuiverDataJob: Unexpected error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise # Re-raise for retry mechanism
  end
end
