# frozen_string_literal: true

namespace :data_fetch do
  desc 'Fetch recent congressional trades from QuiverQuant and store them in quiver_trades'
  task congress_daily: :environment do
    start_date = 60.days.ago.to_date
    end_date   = Date.current

    puts "[data_fetch:congress_daily] Fetching congressional trades from #{start_date} to #{end_date}..."

    # Use GLCommand for audit logging
    command = AuditTrail::LogDataIngestion.call(
      task_name: 'data_fetch:congress_daily',
      data_source: 'quiverquant_congress'
    ) do |_run|
      # Execute the actual fetch
      result = FetchQuiverData.call(start_date: start_date, end_date: end_date)

      raise StandardError, result.full_error_message || result.error unless result.success?

      # Return expected format for logging
      {
        fetched: result.trades_count,
        created: result.new_trades_count,
        updated: result.updated_trades_count,
        skipped: result.trades_count - result.new_trades_count - result.updated_trades_count,
        date_range: [start_date, end_date],
        record_operations: result.record_operations
      }
    end

    if command.success?
      run = command.run
      puts "[data_fetch:congress_daily] ✅ Done: total=#{run.records_fetched}, new=#{run.records_created}, " \
           "updated=#{run.records_updated}"
    else
      # Since LogDataIngestion re-raises, this part might not be reached if an error occurs inside the block.
      # But if the command itself fails for other reasons, we handle it here.
      puts "[data_fetch:congress_daily] ❌ ERROR: #{command.run&.error_message || command.error}"
      exit 1
    end
  end

  desc 'Fetch recent insider trades from QuiverQuant and store them in quiver_trades'
  task insider_daily: :environment do
    start_date = 60.days.ago.to_date
    end_date   = Date.current
    limit      = 1000

    puts "[data_fetch:insider_daily] Fetching insider trades from #{start_date} to #{end_date} (limit=#{limit})..."

    # Use GLCommand for audit logging
    command = AuditTrail::LogDataIngestion.call(
      task_name: 'data_fetch:insider_daily',
      data_source: 'quiverquant_insider'
    ) do |_run|
      # Execute the actual fetch
      result = FetchInsiderTrades.call(start_date: start_date, end_date: end_date, limit: limit)

      raise StandardError, result.full_error_message unless result.success?

      # Return expected format for logging
      {
        fetched: result.total_count,
        created: result.new_count,
        updated: result.updated_count,
        skipped: result.total_count - result.new_count - result.updated_count,
        date_range: [start_date, end_date],
        record_operations: result.record_operations
      }
    end

    if command.success?
      run = command.run
      puts "[data_fetch:insider_daily] ✅ Done: total=#{run.records_fetched}, new=#{run.records_created}, " \
           "updated=#{run.records_updated}"
    else
      puts "[data_fetch:insider_daily] ❌ ERROR: #{command.run&.error_message || command.error}"
      exit 1
    end
  end
end
