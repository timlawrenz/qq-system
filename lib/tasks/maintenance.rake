# frozen_string_literal: true

namespace :maintenance do
  desc 'Run all daily maintenance tasks (blocked assets, etc.)'
  task daily: :environment do
    puts '[maintenance:daily] Starting daily maintenance tasks...'

    # Use GLCommand for audit logging
    command = AuditTrail::LogDataIngestion.call(
      task_name: 'maintenance:daily',
      data_source: 'internal_maintenance'
    ) do |run|
      puts '[maintenance:daily] Running Workflows::DailyMaintenanceChain...'
      result = Workflows::DailyMaintenanceChain.call

      unless result.success?
        raise StandardError, result.full_error_message
      end

      # Return expected format for logging
      {
        fetched: result.total_count,
        created: result.new_count,
        updated: result.updated_count,
        skipped: 0, # Not explicitly tracked in the chain
        record_operations: result.respond_to?(:record_operations) ? result.record_operations : []
      }
    end

    if command.success?
      run = command.run
      puts "[maintenance:daily] Insider trades: total=#{run.records_fetched}, new=#{run.records_created}, " \
           "updated=#{run.records_updated}"
      # Note: removed_count from result is not directly in DataIngestionRun but could be in a more complex mapping
    else
      puts "[maintenance:daily] ERROR: #{command.run&.error_message || command.error}"
      exit 1
    end

    puts '[maintenance:daily] Done.'
  end
end