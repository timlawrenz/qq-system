# frozen_string_literal: true

namespace :data_fetch do
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
