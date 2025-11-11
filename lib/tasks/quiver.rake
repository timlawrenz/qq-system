# frozen_string_literal: true

namespace :quiver do
  desc 'Fetches the last two years of congressional trading signals from the Quiver Quantitative API and stores them'
  task fetch_historical_signals: :environment do
    start_date = 2.years.ago.to_date
    end_date = Date.current

    puts "Fetching congressional trading signals from #{start_date} to #{end_date}..."

    client = QuiverClient.new
    trades_data = client.fetch_congressional_trades(start_date: start_date, end_date: end_date)

    if trades_data.empty?
      puts 'No new trading signals found for the given period.'
      exit
    end

    puts "Processing #{trades_data.size} signals..."
    new_signals_count = 0

    trades_data.each do |trade_data|
      # Use find_or_create_by to avoid duplicates
      quiver_trade = QuiverTrade.find_or_create_by!(
        ticker: trade_data['ticker'],
        transaction_date: trade_data['transaction_date'],
        trader_name: trade_data['trader_name'],
        transaction_type: trade_data['transaction_type']
      ) do |trade|
        trade.company = trade_data['company']
        trade.trader_source = 'congress' # Assuming this source
        trade.trade_size_usd = trade_data['trade_size_usd']
        trade.disclosed_at = trade_data['disclosed_at']
      end

      new_signals_count += 1 if quiver_trade.previously_new_record?
    end

    puts "Finished. Stored #{new_signals_count} new signals."
  rescue Date::Error
    puts 'Error: Invalid date format. Please use YYYY-MM-DD.'
    exit 1
  end
end
