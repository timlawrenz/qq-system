# frozen_string_literal: true

namespace :data_fetch do
  desc 'Fetch recent congressional trades from QuiverQuant and store them in quiver_trades'
  task congress_daily: :environment do
    start_date = 60.days.ago.to_date
    end_date   = Date.current

    puts "[data_fetch:congress_daily] Fetching congressional trades from #{start_date} to #{end_date}..."

    result = FetchQuiverData.call(start_date: start_date, end_date: end_date)

    unless result.success?
      puts "[data_fetch:congress_daily] ERROR: #{result.full_error_message || result.error}"
      exit 1
    end

    puts "[data_fetch:congress_daily] Done: total=#{result.trades_count}, new=#{result.new_trades_count}, " \
         "updated=#{result.updated_trades_count}, errors=#{result.error_count}"

    if result.error_count.positive?
      puts "[data_fetch:congress_daily] WARNING: #{result.error_count} trades failed to save"
    end
  end

  desc 'Fetch recent insider trades from QuiverQuant and store them in quiver_trades'
  task insider_daily: :environment do
    start_date = 60.days.ago.to_date
    end_date   = Date.current
    limit      = 1000

    puts "[data_fetch:insider_daily] Fetching insider trades from #{start_date} to #{end_date} (limit=#{limit})..."

    result = FetchInsiderTrades.call(start_date: start_date, end_date: end_date, limit: limit)

    unless result.success?
      puts "[data_fetch:insider_daily] ERROR: #{result.full_error_message}"
      exit 1
    end

    puts "[data_fetch:insider_daily] Done: total=#{result.total_count}, new=#{result.new_count}, " \
         "updated=#{result.updated_count}, errors=#{result.error_count}"

    if result.error_count.positive? && result.respond_to?(:error_messages)
      puts "[data_fetch:insider_daily] Error details:"
      Array(result.error_messages).each do |msg|
        puts "  - #{msg}"
      end
    end
  end
end
