# frozen_string_literal: true

# FetchQuiverData Command
#
# Fetches congressional trading data from QuiverQuant API and persists to database.
# This command is the critical missing piece that enables the automated trading pipeline.
#
# Responsibilities:
# 1. Fetch trades from QuiverQuant API using existing QuiverClient
# 2. Deduplicate and persist trades to QuiverTrade table
# 3. Handle errors gracefully (continue on individual failures, fail fast on API errors)
# 4. Return detailed counts for monitoring
#
# Usage:
#   FetchQuiverData.call(start_date: 60.days.ago.to_date, end_date: Date.today)
#   FetchQuiverData.call(ticker: 'AAPL')
class FetchQuiverData < GLCommand::Callable
  allows :start_date, :end_date, :ticker
  returns :trades_count, :new_trades_count, :updated_trades_count, :error_count

  def call
    # Step 1: Initialize counters
    context.trades_count = 0
    context.new_trades_count = 0
    context.updated_trades_count = 0
    context.error_count = 0

    # Step 2: Fetch from API using existing QuiverClient
    trades_data = fetch_from_api
    context.trades_count = trades_data.size

    Rails.logger.info("FetchQuiverData: Received #{trades_data.size} trades from API")

    # Step 3: Process each trade (save or update)
    trades_data.each do |trade_attrs|
      process_trade(trade_attrs)
    end

    # Step 4: Log summary
    log_summary

    context
  end

  private

  def fetch_from_api
    client = QuiverClient.new
    client.fetch_congressional_trades(
      start_date: context.start_date || 60.days.ago.to_date,
      end_date: context.end_date || Time.zone.today,
      ticker: context.ticker
    )
  rescue StandardError => e
    Rails.logger.error("FetchQuiverData: API fetch failed: #{e.message}")
    stop_and_fail!("Failed to fetch data from Quiver API: #{e.message}")
  end

  def process_trade(trade_attrs)
    # Find or create based on unique composite key
    # Composite key: ticker + trader_name + transaction_date
    # Rationale: Same person can trade same stock on different dates,
    # but unlikely to have duplicate trades on same date
    trade = QuiverTrade.find_or_initialize_by(
      ticker: trade_attrs[:ticker],
      trader_name: trade_attrs[:trader_name],
      transaction_date: trade_attrs[:transaction_date]
    )

    is_new = trade.new_record?

    # Assign attributes
    trade.assign_attributes(
      company: trade_attrs[:company],
      trader_source: trade_attrs[:trader_source],
      transaction_type: trade_attrs[:transaction_type],
      trade_size_usd: trade_attrs[:trade_size_usd],
      disclosed_at: trade_attrs[:disclosed_at]
    )

    # Save if new or changed
    if trade.changed?
      trade.save!
      if is_new
        context.new_trades_count += 1
      else
        context.updated_trades_count += 1
      end
    end
  rescue StandardError => e
    context.error_count += 1
    Rails.logger.error(
      "FetchQuiverData: Failed to save trade #{trade_attrs[:ticker]}/#{trade_attrs[:trader_name]}: #{e.message}"
    )
    # Continue processing other trades - don't fail entire command for one bad trade
  end

  def log_summary
    Rails.logger.info(
      "FetchQuiverData: Processed #{context.trades_count} trades - " \
      "#{context.new_trades_count} new, " \
      "#{context.updated_trades_count} updated, " \
      "#{context.error_count} errors"
    )
  end
end
