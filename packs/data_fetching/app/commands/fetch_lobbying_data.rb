# frozen_string_literal: true

# FetchLobbyingData Command
#
# Fetches corporate lobbying disclosure data from QuiverQuant API (Tier 2)
# and persists to database.
#
# Key Characteristics:
# - API is ticker-specific (not bulk) - must iterate over ticker list
# - Companies use multiple lobbying firms per quarter
# - Unique constraint: ticker + quarter + registrant
# - Gracefully handles missing data (404 = no lobbying activity)
#
# Responsibilities:
# 1. Fetch lobbying data for list of tickers using QuiverClient
# 2. Deduplicate and persist records to LobbyingExpenditure table
# 3. Handle errors gracefully (continue on individual ticker failures)
# 4. Return detailed counts for monitoring
#
# Usage:
#   FetchLobbyingData.call(tickers: ['GOOGL', 'AAPL', 'JPM'])
#   FetchLobbyingData.call(tickers: ['GOOGL'])
#
# Example Output:
#   {
#     total_records: 100,
#     new_records: 80,
#     updated_records: 20,
#     tickers_processed: 3,
#     tickers_failed: 0,
#     errors: []
#   }
class FetchLobbyingData < GLCommand::Callable
  # rubocop:disable Metrics/AbcSize
  allows :tickers, array_of: String
  returns :total_records, :new_records, :updated_records, :tickers_processed, :tickers_failed, :failed_tickers,
          :api_calls

  def call
    # Validate inputs
    validate_tickers!

    # Initialize counters
    context.total_records = 0
    context.new_records = 0
    context.updated_records = 0
    context.tickers_processed = 0
    context.tickers_failed = 0
    context.failed_tickers = []
    context.api_calls = []

    # Process each ticker
    Rails.logger.info("FetchLobbyingData: Starting fetch for #{context.tickers.size} tickers")

    client = QuiverClient.new
    context.tickers.each do |ticker|
      process_ticker(ticker, client)
    end
    context.api_calls = client.api_calls

    # Log summary
    log_summary

    context
  rescue StandardError => e
    context.api_calls = client.api_calls if client
    stop_and_fail!(e.message)
  end

  private

  def validate_tickers!
    stop_and_fail!('No tickers provided. Please provide an array of ticker symbols.') if context.tickers.blank?

    return unless context.tickers.size > 100

    Rails.logger.warn("FetchLobbyingData: Large ticker list (#{context.tickers.size}). Consider batching.")
  end

  def process_ticker(ticker, client)
    Rails.logger.info("FetchLobbyingData: Processing #{ticker}")

    # Fetch from API
    lobbying_records = client.fetch_lobbying_data(ticker)

    # Process each record
    lobbying_records.each do |record_data|
      process_record(record_data)
    end

    context.tickers_processed += 1
    Rails.logger.info("FetchLobbyingData: Completed #{ticker} - #{lobbying_records.size} records")
  rescue StandardError => e
    context.tickers_failed += 1
    error_msg = "Failed to process #{ticker}: #{e.message}"
    context.failed_tickers << { ticker: ticker, error: e.message }
    Rails.logger.error("FetchLobbyingData: #{error_msg}")
    # Continue processing other tickers
  end

  def process_record(record_data)
    # Find or initialize based on unique composite key
    # Composite key: ticker + quarter + registrant
    # Rationale: Company can use multiple lobbying firms per quarter
    lobbying = LobbyingExpenditure.find_or_initialize_by(
      ticker: record_data[:ticker],
      quarter: record_data[:quarter],
      registrant: record_data[:registrant]
    )

    is_new = lobbying.new_record?

    # Assign attributes
    lobbying.assign_attributes(
      date: record_data[:date],
      amount: record_data[:amount] || 0.0,
      client: record_data[:client],
      issue: record_data[:issue],
      specific_issue: record_data[:specific_issue]
    )

    # Save and update counters
    if lobbying.save
      context.total_records += 1
      is_new ? context.new_records += 1 : context.updated_records += 1
    else
      error_msg = "Failed to save record: #{lobbying.errors.full_messages.join(', ')}"
      Rails.logger.error("FetchLobbyingData: #{error_msg}")
    end
  rescue StandardError => e
    error_msg = "Failed to process record for #{record_data[:ticker]}/#{record_data[:quarter]}: #{e.message}"
    Rails.logger.error("FetchLobbyingData: #{error_msg}")
    # Continue processing other records
  end

  def log_summary
    Rails.logger.info(
      'FetchLobbyingData: Complete - ' \
      "Tickers: #{context.tickers_processed}/#{context.tickers.size} processed, " \
      "Records: #{context.total_records} total (#{context.new_records} new, #{context.updated_records} updated), " \
      "Failed: #{context.failed_tickers.size}"
    )

    return unless context.failed_tickers.any?

    Rails.logger.warn('FetchLobbyingData: Failed tickers:')
    context.failed_tickers.first(5).each do |failure|
      Rails.logger.warn("  - #{failure[:ticker]}: #{failure[:error]}")
    end
    Rails.logger.warn("  ... and #{context.failed_tickers.size - 5} more") if context.failed_tickers.size > 5
  end
  # rubocop:enable Metrics/AbcSize
end
