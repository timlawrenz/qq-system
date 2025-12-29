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

  desc 'Purge API payloads older than 2 years (retention policy)'
  task purge_old_api_payloads: :environment do
    cutoff_date = 2.years.ago
    
    puts "[maintenance:purge_old_api_payloads] Starting cleanup for records older than #{cutoff_date.to_date}..."
    
    # Count before deletion
    old_payloads = AuditTrail::ApiPayload.where('created_at < ?', cutoff_date)
    count = old_payloads.count
    
    if count.zero?
      puts '[maintenance:purge_old_api_payloads] No old API payloads to purge.'
      next
    end
    
    puts "[maintenance:purge_old_api_payloads] Found #{count} API payloads to purge..."
    
    # Delete in batches to avoid locking issues
    deleted = 0
    old_payloads.in_batches(of: 1000) do |batch|
      batch_count = batch.destroy_all.size
      deleted += batch_count
      puts "  Deleted batch: #{batch_count} records (#{deleted}/#{count})"
    end
    
    puts "[maintenance:purge_old_api_payloads] Successfully purged #{deleted} API payloads."
    puts "[maintenance:purge_old_api_payloads] Done."
  end

  desc 'Show current database storage statistics'
  task storage_stats: :environment do
    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "💾 Audit Trail Storage Statistics"
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    
    stats = {
      'Data Ingestion Runs' => AuditTrail::DataIngestionRun.count,
      'Data Ingestion Run Records' => AuditTrail::DataIngestionRunRecord.count,
      'API Payloads' => AuditTrail::ApiPayload.count,
      'API Call Logs' => AuditTrail::ApiCallLog.count,
      'Trade Decisions' => AuditTrail::TradeDecision.count,
      'Trade Executions' => AuditTrail::TradeExecution.count
    }
    
    stats.each do |table, count|
      printf "%-30s %10d records\n", table, count
    end
    
    # Age of oldest records
    puts "\n📅 Oldest Records:"
    oldest_payload = AuditTrail::ApiPayload.order(:created_at).first
    if oldest_payload
      puts "  API Payloads: #{oldest_payload.created_at.to_date} (#{((Date.current - oldest_payload.created_at.to_date) / 365).round(1)} years old)"
    end
    
    oldest_decision = AuditTrail::TradeDecision.order(:created_at).first
    if oldest_decision
      puts "  Trade Decisions: #{oldest_decision.created_at.to_date} (#{((Date.current - oldest_decision.created_at.to_date) / 365).round(1)} years old)"
    end
    
    # Recommend cleanup if needed
    two_years_ago = 2.years.ago
    old_payload_count = AuditTrail::ApiPayload.where('created_at < ?', two_years_ago).count
    
    if old_payload_count.positive?
      puts "\n⚠️  Recommendation:"
      puts "  Found #{old_payload_count} API payloads older than 2 years."
      puts "  Consider running: rake maintenance:purge_old_api_payloads"
    end
    
    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  end
end