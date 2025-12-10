# frozen_string_literal: true

# FetchLobbyingDataJob
#
# Background job that fetches corporate lobbying disclosure data from QuiverQuant API (Tier 2).
# This job should run quarterly to refresh lobbying data after quarterly disclosure deadlines.
#
# Key Characteristics:
# - API is ticker-specific (not bulk) - must provide ticker list
# - Lobbying disclosures filed quarterly with 45-day lag
# - Rate limit: 1,000 calls/day (can fetch 1,000 tickers/day)
#
# Recommended Schedule:
#   - Mid-February: Fetch Q4 data (45 days after Dec 31)
#   - Mid-May: Fetch Q1 data (45 days after Mar 31)
#   - Mid-August: Fetch Q2 data (45 days after Jun 30)
#   - Mid-November: Fetch Q3 data (45 days after Sep 30)
#
# Responsibilities:
# 1. Call FetchLobbyingData command with ticker universe
# 2. Handle success/failure with clear logging
# 3. Retry on failure with exponential backoff
# 4. Alert on high failure rates
#
# Usage:
#   FetchLobbyingDataJob.perform_now
#   FetchLobbyingDataJob.perform_now(tickers: ['GOOGL', 'AAPL'])
#   FetchLobbyingDataJob.perform_later(tickers: SP500_TICKERS)
class FetchLobbyingDataJob < ApplicationJob
  queue_as :default

  # Retry configuration: 3 attempts with exponential backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(tickers: nil)
    tickers ||= default_ticker_universe

    Rails.logger.info('=' * 80)
    Rails.logger.info('FetchLobbyingDataJob: Starting lobbying data fetch')
    Rails.logger.info("  Tickers: #{tickers.size} tickers")
    Rails.logger.info("  First 5: #{tickers.first(5).join(', ')}")
    Rails.logger.info('=' * 80)

    # Call the command
    result = FetchLobbyingData.call(tickers: tickers)

    # Handle result
    if result.success?
      Rails.logger.info(
        'FetchLobbyingDataJob: SUCCESS - ' \
        "Processed #{result.tickers_processed}/#{tickers.size} tickers, " \
        "#{result.total_records} records " \
        "(#{result.new_records} new, #{result.updated_records} updated)"
      )

      # Alert if high failure rate (>20%)
      if result.tickers_failed.positive?
        failure_rate = (result.tickers_failed.to_f / tickers.size * 100).round(1)
        
        if failure_rate > 20.0
          Rails.logger.error(
            'FetchLobbyingDataJob: HIGH FAILURE RATE - ' \
            "#{result.tickers_failed} tickers failed (#{failure_rate}% failure rate)"
          )
          
          # Log first few failures for debugging
          if result.failed_tickers.any?
            Rails.logger.error('Failed tickers:')
            result.failed_tickers.first(5).each do |failure|
              Rails.logger.error("  - #{failure[:ticker]}: #{failure[:error]}")
            end
          end
        else
          Rails.logger.warn(
            "FetchLobbyingDataJob: #{result.tickers_failed} tickers failed (#{failure_rate}% failure rate)"
          )
        end
      end
    else
      Rails.logger.error("FetchLobbyingDataJob: FAILED - #{result.error}")
      raise result.error # Re-raise to mark job as failed for retry
    end

    Rails.logger.info('=' * 80)
    Rails.logger.info('FetchLobbyingDataJob: Complete')
    Rails.logger.info('=' * 80)
    
  rescue StandardError => e
    Rails.logger.error("FetchLobbyingDataJob: Unexpected error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise # Re-raise for retry mechanism
  end

  private

  def default_ticker_universe
    # Default to top lobbying companies across key sectors
    # Tech giants, financial institutions, healthcare, energy, defense
    #
    # For production, this should be:
    # - S&P 500 tickers (500 companies)
    # - Or dynamically loaded from a ticker universe table
    # - Or filtered by industry (tech, finance, healthcare have highest lobbying)
    #
    # Rate limit consideration:
    # - 1,000 calls/day limit
    # - S&P 500 = 500 calls (fits in 1 day)
    # - Russell 3000 = 3,000 calls (requires 3 days with batching)
    %w[
      GOOGL AAPL MSFT AMZN META
      JPM BAC GS MS C WFC
      JNJ PFE MRK ABT BMY LLY
      CVX XOM COP BP SLB
      BA LMT RTX NOC GD
      T VZ TMUS
      WMT TGT HD LOW
      DIS NFLX CMCSA
      NVDA AMD INTC QCOM AVGO
      UNH CVS CI ANTM HUM
    ]
  end
end
