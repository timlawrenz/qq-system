# frozen_string_literal: true

# FetchGovernmentContractsJob
#
# Background job that fetches recent government contract awards from QuiverQuant.
class FetchGovernmentContractsJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(start_date: nil, end_date: nil, lookback_days: nil, limit: nil)
    Rails.logger.info('=' * 80)
    Rails.logger.info('FetchGovernmentContractsJob: Starting contracts data fetch')
    Rails.logger.info("  start_date: #{start_date || 'lookback-based'}")
    Rails.logger.info("  end_date: #{end_date || 'today'}")
    Rails.logger.info("  lookback_days: #{lookback_days || 90}")
    Rails.logger.info("  limit: #{limit || 1000}")
    Rails.logger.info('=' * 80)

    result = FetchGovernmentContracts.call(
      start_date: start_date,
      end_date: end_date,
      lookback_days: lookback_days,
      limit: limit
    )

    if result.success?
      Rails.logger.info(
        "FetchGovernmentContractsJob: SUCCESS - total=#{result.total_count}, new=#{result.new_count}, updated=#{result.updated_count}, errors=#{result.error_count}"
      )

      if result.error_count.positive? && result.respond_to?(:error_messages)
        Rails.logger.warn('FetchGovernmentContractsJob: error messages (first 5):')
        Array(result.error_messages).first(5).each do |msg|
          Rails.logger.warn("  - #{msg}")
        end
      end
    else
      Rails.logger.error("FetchGovernmentContractsJob: FAILED - #{result.full_error_message}")
      raise result.error || StandardError.new(result.full_error_message)
    end

    Rails.logger.info('=' * 80)
    Rails.logger.info('FetchGovernmentContractsJob: Complete')
    Rails.logger.info('=' * 80)
  rescue StandardError => e
    Rails.logger.error("FetchGovernmentContractsJob: Unexpected error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    raise
  end
end
