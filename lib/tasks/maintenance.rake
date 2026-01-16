# frozen_string_literal: true

namespace :maintenance do
  desc 'Run all daily maintenance tasks (blocked assets, etc.)'
  task daily: :environment do
    puts '[maintenance:daily] Starting daily maintenance tasks...'

    # Use GLCommand for audit logging
    profiles_summary = nil
    quiver_summary = nil
    insider_summary = nil
    chain_result = nil

    command = AuditTrail::LogDataIngestion.call(
      task_name: 'maintenance:daily',
      data_source: 'internal_maintenance'
    ) do |_run|
      puts '[maintenance:daily] Running Workflows::DailyMaintenanceChain...'
      result = Workflows::DailyMaintenanceChain.call
      chain_result = result

      profiles_summary = {
        tickers_seen: result.respond_to?(:tickers_seen) ? result.tickers_seen : nil,
        refreshed: result.respond_to?(:profiles_refreshed) ? result.profiles_refreshed : nil,
        skipped: result.respond_to?(:profiles_skipped) ? result.profiles_skipped : nil,
        failed: result.respond_to?(:profiles_failed) ? result.profiles_failed : nil
      }

      quiver_summary = {
        fetched: result.respond_to?(:trades_count) ? result.trades_count : 0,
        created: result.respond_to?(:new_trades_count) ? result.new_trades_count : 0,
        updated: result.respond_to?(:updated_trades_count) ? result.updated_trades_count : 0
      }

      insider_summary = {
        fetched: result.respond_to?(:total_count) ? result.total_count : 0,
        created: result.respond_to?(:new_count) ? result.new_count : 0,
        updated: result.respond_to?(:updated_count) ? result.updated_count : 0
      }

      raise StandardError, result.full_error_message unless result.success?

      # Return expected format for logging
      {
        fetched: (quiver_summary[:fetched] || 0) + (insider_summary[:fetched] || 0),
        created: (quiver_summary[:created] || 0) + (insider_summary[:created] || 0),
        updated: (quiver_summary[:updated] || 0) + (insider_summary[:updated] || 0),
        skipped: 0, # Not explicitly tracked in the chain
        record_operations: result.respond_to?(:record_operations) ? result.record_operations : []
      }
    end

    if command.success?
      run = command.run
      puts "[maintenance:daily] Total processed: fetched=#{run.records_fetched}, new=#{run.records_created}, " \
           "updated=#{run.records_updated}"

      if quiver_summary
        puts "[maintenance:daily] Congressional trades: total=#{quiver_summary[:fetched]}, new=#{quiver_summary[:created]}, updated=#{quiver_summary[:updated]}"
      end

      if insider_summary
        puts "[maintenance:daily] Insider trades: total=#{insider_summary[:fetched]}, new=#{insider_summary[:created]}, updated=#{insider_summary[:updated]}"
      end

      if chain_result&.contracts_stats
        s = chain_result.contracts_stats
        puts "[maintenance:daily] Government Contracts: total=#{s[:fetched]}, new=#{s[:created]}, updated=#{s[:updated]}"
      end

      if chain_result&.lobbying_stats
        s = chain_result.lobbying_stats
        puts "[maintenance:daily] Lobbying Data: total=#{s[:total]}, new=#{s[:new]}, updated=#{s[:updated]}"
      end

      if chain_result&.committee_stats
        s = chain_result.committee_stats
        puts "[maintenance:daily] Committee Sync: created=#{s[:memberships_created]}, committees=#{s[:committees_processed]}"
      end

      if chain_result&.scoring_stats
        s = chain_result.scoring_stats
        puts "[maintenance:daily] Politician Scoring: profiles=#{s[:profiles]}, scored=#{s[:scored]}, created=#{s[:created]}"
      end

      if profiles_summary && profiles_summary[:tickers_seen]
        puts "[maintenance:daily] Company profiles: tickers=#{profiles_summary[:tickers_seen]}, " \
             "refreshed=#{profiles_summary[:refreshed]}, skipped=#{profiles_summary[:skipped]}, failed=#{profiles_summary[:failed]}"
      end

      # NOTE: removed_count from result is not directly in DataIngestionRun but could be in a more complex mapping
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
    old_payloads = AuditTrail::ApiPayload.where(created_at: ...cutoff_date)
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
    puts '[maintenance:purge_old_api_payloads] Done.'
  end

  desc 'Show current database storage statistics'
  task storage_stats: :environment do
    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts '💾 Audit Trail Storage Statistics'
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
    old_payload_count = AuditTrail::ApiPayload.where(created_at: ...two_years_ago).count

    if old_payload_count.positive?
      puts "\n⚠️  Recommendation:"
      puts "  Found #{old_payload_count} API payloads older than 2 years."
      puts '  Consider running: rake maintenance:purge_old_api_payloads'
    end

    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  end
end
