# frozen_string_literal: true

namespace :performance do
  desc 'Generate weekly performance report(s) and persist PerformanceSnapshot records'
  task weekly_report: :environment do
    puts '[performance:weekly_report] Generating performance report(s)...'

    # This report measures the *portfolio* (single Alpaca account), not individual signal strategies.
    base_name = ENV.fetch('PERFORMANCE_PORTFOLIO_NAME', 'Blended Portfolio')
    trading_mode = ENV.fetch('TRADING_MODE')

    # Keep weekly snapshots separate per trading mode by including mode in the snapshot strategy_name.
    portfolio_name = "#{base_name} (#{trading_mode})"

    result = GeneratePerformanceReport.call(strategy_name: portfolio_name)

    if result.success?
      puts(
        "[performance:weekly_report] OK: #{portfolio_name} => #{result.file_path} " \
        "(snapshot_id=#{result.snapshot_id})"
      )
    else
      message = if result.respond_to?(:full_error_message)
                  result.full_error_message
                elsif result.errors.respond_to?(:full_messages)
                  result.errors.full_messages.join(', ')
                else
                  result.errors.to_s
                end

      warn "[performance:weekly_report] ERROR: #{portfolio_name} => #{message}"
      exit 1
    end

    puts '[performance:weekly_report] Done.'
  end
end
