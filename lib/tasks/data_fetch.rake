# frozen_string_literal: true

namespace :data_fetch do
  desc 'Fetch recent congressional trades from QuiverQuant and store them in quiver_trades'
  task congress_daily: :environment do
    start_date = 60.days.ago.to_date
    end_date   = Date.current

    puts "[data_fetch:congress_daily] Fetching congressional trades from #{start_date} to #{end_date}..."

    # Wrap with audit logging
    logger = AuditTrail::LogDataIngestion.new(
      task_name: 'data_fetch:congress_daily',
      data_source: 'quiverquant_congress'
    )

    success = logger.call do |run|
      # Execute the actual fetch
      result = FetchQuiverData.call(start_date: start_date, end_date: end_date)

      unless result.success?
        raise StandardError, result.full_error_message || result.error
      end

      # Return expected format for logging
      {
        fetched: result.trades_count,
        created: result.new_trades_count,
        updated: result.updated_trades_count,
        skipped: result.trades_count - result.new_trades_count - result.updated_trades_count,
        date_range: [start_date, end_date]
      }
    end

    if success
      run = logger.run
      puts "[data_fetch:congress_daily] ✅ Done: total=#{run.records_fetched}, new=#{run.records_created}, " \
           "updated=#{run.records_updated}"
    else
      puts "[data_fetch:congress_daily] ❌ ERROR: #{logger.run.error_message}"
      exit 1
    end
  end

  desc 'Fetch recent insider trades from QuiverQuant and store them in quiver_trades'
  task insider_daily: :environment do
    start_date = 60.days.ago.to_date
    end_date   = Date.current
    limit      = 1000

    puts "[data_fetch:insider_daily] Fetching insider trades from #{start_date} to #{end_date} (limit=#{limit})..."

    # Wrap with audit logging
    logger = AuditTrail::LogDataIngestion.new(
      task_name: 'data_fetch:insider_daily',
      data_source: 'quiverquant_insider'
    )

    success = logger.call do |run|
      # Execute the actual fetch
      result = FetchInsiderTrades.call(start_date: start_date, end_date: end_date, limit: limit)

      unless result.success?
        raise StandardError, result.full_error_message
      end

      # Return expected format for logging
      {
        fetched: result.total_count,
        created: result.new_count,
        updated: result.updated_count,
        skipped: 0,
        date_range: [start_date, end_date]
      }
    end

    if success
      run = logger.run
      puts "[data_fetch:insider_daily] ✅ Done: total=#{run.records_fetched}, new=#{run.records_created}, " \
           "updated=#{run.records_updated}"
    else
      puts "[data_fetch:insider_daily] ❌ ERROR: #{logger.run.error_message}"
      exit 1
    end
  end
end
