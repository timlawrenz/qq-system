# frozen_string_literal: true

namespace :maintenance do
  desc 'Run all daily maintenance tasks (blocked assets, etc.)'
  task daily: :environment do
    puts '[maintenance:daily] Starting daily maintenance tasks...'

    puts '[maintenance:daily] Running Workflows::DailyMaintenanceChain...'
    result = Workflows::DailyMaintenanceChain.call

    if result.success?
      puts "[maintenance:daily] Insider trades: total=#{result.total_count}, new=#{result.new_count}, " \
           "updated=#{result.updated_count}, errors=#{result.error_count}"
      puts "[maintenance:daily] Blocked assets removed: #{result.removed_count}"
    else
      puts "[maintenance:daily] ERROR: #{result.full_error_message}"
      exit 1
    end

    puts '[maintenance:daily] Done.'
  end
end
