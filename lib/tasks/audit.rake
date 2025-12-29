# frozen_string_literal: true

namespace :audit do
  desc 'Generate symbol activity report for a given symbol and date range'
  task :symbol_report, [:symbol, :start_date, :end_date] => :environment do |_t, args|
    symbol = args[:symbol] || ENV.fetch('SYMBOL', nil)
    start_date = args[:start_date] || ENV.fetch('START_DATE', 1.month.ago.to_date.to_s)
    end_date = args[:end_date] || ENV.fetch('END_DATE', Date.current.to_s)

    unless symbol
      puts 'Error: Symbol is required'
      puts 'Usage: rake audit:symbol_report[AAPL,2025-01-01,2025-12-31]'
      puts '   or: SYMBOL=AAPL START_DATE=2025-01-01 END_DATE=2025-12-31 rake audit:symbol_report'
      exit 1
    end

    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "📊 Symbol Activity Report: #{symbol}"
    puts "📅 Period: #{start_date} to #{end_date}"
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

    report = AuditTrail::SymbolActivityReport.generate(
      symbol: symbol,
      start_date: start_date,
      end_date: end_date
    )

    # Summary
    summary = report[:summary]
    puts "📈 Summary:"
    puts "  Total Decisions: #{summary[:total_decisions]}"
    puts "  Executed: #{summary[:executed_count]} (#{summary[:success_rate]}%)"
    puts "  Failed: #{summary[:failed_count]}"
    puts

    # Data Ingested
    puts "📥 Data Ingested (#{report[:data_ingested].size} records):"
    if report[:data_ingested].any?
      report[:data_ingested].first(5).each do |data|
        puts "  #{data[:date]} | #{data[:trader]} | #{data[:type]} | $#{data[:size]}"
      end
      puts "  ... (showing first 5)" if report[:data_ingested].size > 5
    else
      puts "  (none)"
    end
    puts

    # Decisions Made
    puts "🎯 Decisions Made (#{report[:decisions_made].size} decisions):"
    if report[:decisions_made].any?
      report[:decisions_made].first(5).each do |decision|
        puts "  #{decision[:created_at].strftime('%Y-%m-%d %H:%M')} | #{decision[:strategy]} | " \
             "#{decision[:side].upcase} #{decision[:quantity]} | #{decision[:status]}"
      end
      puts "  ... (showing first 5)" if report[:decisions_made].size > 5
    else
      puts "  (none)"
    end
    puts

    # Trades Executed
    puts "💰 Trades Executed (#{report[:trades_executed].size} executions):"
    if report[:trades_executed].any?
      report[:trades_executed].first(5).each do |execution|
        if execution[:status] == 'filled'
          puts "  ✅ #{execution[:executed_at].strftime('%Y-%m-%d %H:%M')} | " \
               "#{execution[:filled_qty]} @ $#{execution[:filled_price]}"
        else
          puts "  ❌ #{execution[:executed_at].strftime('%Y-%m-%d %H:%M')} | " \
               "#{execution[:status]} | #{execution[:error]}"
        end
      end
      puts "  ... (showing first 5)" if report[:trades_executed].size > 5
    else
      puts "  (none)"
    end

    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  end

  desc 'Generate strategy performance report'
  task :strategy_performance, [:strategy_name] => :environment do |_t, args|
    strategy_name = args[:strategy_name] || ENV.fetch('STRATEGY', nil)

    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "📊 Strategy Performance Report"
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

    results = AuditTrail::StrategyPerformanceReport.generate(strategy_name: strategy_name)

    if results.empty?
      puts "No strategies found."
      exit 0
    end

    # Table header
    printf "%-40s %10s %10s %10s %10s %12s\n",
           'Strategy', 'Signals', 'Executed', 'Failed', 'Cancelled', 'Success Rate'
    puts "─" * 100

    # Table rows
    results.each do |result|
      printf "%-40s %10d %10d %10d %10d %11.2f%%\n",
             result[:strategy].truncate(40),
             result[:total_signals],
             result[:executed],
             result[:failed],
             result[:cancelled],
             result[:success_rate]
    end

    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  end

  desc 'Generate daily summary of trading activity'
  task :daily_summary, [:date] => :environment do |_t, args|
    date = args[:date] ? Date.parse(args[:date]) : Date.yesterday

    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "📊 Daily Trading Summary: #{date}"
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

    # Data Ingestion
    ingestion_runs = AuditTrail::DataIngestionRun.where(
      created_at: date.beginning_of_day..date.end_of_day
    )
    puts "📥 Data Ingestion:"
    puts "  Runs: #{ingestion_runs.count}"
    puts "  Records Fetched: #{ingestion_runs.sum(:records_fetched)}"
    puts "  Records Created: #{ingestion_runs.sum(:records_created)}"
    puts

    # Trade Decisions
    decisions = AuditTrail::TradeDecision.where(
      created_at: date.beginning_of_day..date.end_of_day
    )
    total_decisions = decisions.count
    executed = decisions.where(status: 'executed').count
    failed = decisions.where(status: 'failed').count
    pending = decisions.where(status: 'pending').count

    puts "🎯 Trade Decisions:"
    puts "  Total: #{total_decisions}"
    puts "  Executed: #{executed} (#{total_decisions.positive? ? (executed.to_f / total_decisions * 100).round(2) : 0}%)"
    puts "  Failed: #{failed}"
    puts "  Pending: #{pending}"
    puts

    # Strategy Breakdown
    if total_decisions.positive?
      puts "📈 By Strategy:"
      decisions.group(:strategy_name).count.sort_by { |_k, v| -v }.each do |strategy, count|
        puts "  #{strategy}: #{count} decisions"
      end
      puts
    end

    # Failure Analysis (if any failures)
    if failed.positive?
      puts "❌ Failure Analysis:"
      failure_report = AuditTrail::FailureAnalysisReport.generate(
        start_date: date,
        end_date: date
      )
      failure_report[:failures_by_reason].each do |reason, count|
        puts "  #{reason}: #{count}"
      end
      puts
    end

    # Alert conditions
    alerts = []
    alerts << "⚠️  ALERT: No data ingestion runs today!" if ingestion_runs.count.zero?
    alerts << "⚠️  ALERT: High failure rate (#{(failed.to_f / total_decisions * 100).round}%)" if total_decisions.positive? && (failed.to_f / total_decisions) > 0.3
    alerts << "⚠️  ALERT: #{pending} decisions still pending" if pending > 5

    if alerts.any?
      puts "🚨 Alerts:"
      alerts.each { |alert| puts "  #{alert}" }
      puts
    end

    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  end

  desc 'Quick audit analysis (alias for failure_analysis with defaults)'
  task :analyze => :environment do
    # Run failure analysis for last 7 days
    Rake::Task['audit:failure_analysis'].invoke
  end

  desc 'Generate failure analysis report'
  task :failure_analysis, [:start_date, :end_date, :strategy] => :environment do |_t, args|
    start_date = args[:start_date] || ENV.fetch('START_DATE', 7.days.ago.to_date.to_s)
    end_date = args[:end_date] || ENV.fetch('END_DATE', Date.current.to_s)
    strategy = args[:strategy] || ENV.fetch('STRATEGY', nil)

    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "❌ Failure Analysis Report"
    puts "📅 Period: #{start_date} to #{end_date}"
    puts "🎯 Strategy: #{strategy || 'All'}"
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

    report = AuditTrail::FailureAnalysisReport.generate(
      start_date: start_date,
      end_date: end_date,
      strategy_name: strategy
    )

    puts "📊 Overview:"
    puts "  Total Decisions: #{report[:total_decisions]}"
    puts "  Failed Decisions: #{report[:failed_decisions]}"
    puts "  Failure Rate: #{report[:failure_rate]}%"
    puts

    if report[:failures_by_reason].any?
      puts "📋 Failures by Reason:"
      report[:failures_by_reason].sort_by { |_k, v| -v }.each do |reason, count|
        percentage = (count.to_f / report[:failed_decisions] * 100).round(1)
        puts "  #{reason}: #{count} (#{percentage}%)"
      end
      puts
    end

    if report[:failures_by_symbol].any?
      puts "📉 Top Failing Symbols:"
      report[:failures_by_symbol].first(10).each do |symbol, count|
        puts "  #{symbol}: #{count} failures"
      end
      puts
    end

    if report[:top_error_messages].any?
      puts "💬 Top Error Messages:"
      report[:top_error_messages].first(5).each do |msg, count|
        puts "  [#{count}x] #{msg.truncate(80)}"
      end
      puts
    end

    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  end
end
