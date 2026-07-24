# frozen_string_literal: true

namespace :performance do
  desc 'Compare the live portfolio cashflows to a hypothetical SPY-only portfolio'
  task spy_benchmark: :environment do
    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "📊 SPY Benchmark Simulation"
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

    alpaca = AlpacaService.new
    comparator = BenchmarkComparator.new(alpaca_service: alpaca)

    # 1. Fetch lifetime cash transfers
    puts "Fetching cash transfers..."
    cash_transfers = alpaca.cash_transfers(start_date: Date.new(2000, 1, 1), end_date: Date.current)
    if cash_transfers.empty?
      puts "No cash transfers found."
      exit
    end

    cash_transfers.sort_by! { |t| t[:date] }
    start_date = cash_transfers.first[:date]

    # 2. Fetch SPY prices
    puts "Fetching SPY historical data..."
    spy_bars = comparator.send(:fetch_spy_bars, start_date - 5.days, Date.current)
    if spy_bars.blank?
      puts "Failed to fetch SPY bars."
      exit
    end

    # Build price lookup
    spy_prices = {}
    spy_bars.each do |bar|
      t = bar[:timestamp] || bar['t'] || bar['timestamp'] || bar[:time]
      date = Time.zone.parse(t.to_s).to_date rescue nil
      next unless date
      
      close_price = bar[:close] || bar['c'] || bar['close']
      spy_prices[date] = close_price.to_f
    end

    sorted_dates = spy_prices.keys.sort

    def nearest_price(date, prices_hash, sorted_dates)
      return prices_hash[date] if prices_hash[date]
      
      prev_dates = sorted_dates.select { |d| d <= date }
      if prev_dates.empty?
        prices_hash[sorted_dates.first]
      else
        prices_hash[prev_dates.last]
      end
    end

    spy_shares = 0.0
    total_deposited = 0.0

    puts "\nSimulating SPY Portfolio (fractional shares matching cash flow):"
    puts "----------------------------------------------------------------"

    cash_transfers.each do |transfer|
      date = transfer[:date]
      amount = transfer[:amount].to_f
      total_deposited += amount
      
      price = nearest_price(date, spy_prices, sorted_dates)
      shares_bought = amount / price
      spy_shares += shares_bought
      
      action = amount > 0 ? "Deposit" : "Withdrawal"
      puts "#{date.to_s.ljust(12)} #{action.ljust(12)} $#{format('%.2f', amount).rjust(8)} -> Bought/Sold #{format('%.4f', shares_bought).rjust(8)} SPY @ $#{format('%.2f', price)}"
    end

    latest_price = spy_prices[sorted_dates.last]
    spy_portfolio_value = spy_shares * latest_price

    current_equity = alpaca.account_equity.to_f

    spy_profit = spy_portfolio_value - total_deposited
    live_profit = current_equity - total_deposited

    spy_pct = (spy_profit / total_deposited) * 100
    live_pct = (live_profit / total_deposited) * 100

    diff = live_profit - spy_profit
    diff_pct = live_pct - spy_pct
    
    sign = diff > 0 ? '+' : ''

    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "📈 SUMMARY"
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "Total Cash Deposited:   $#{format('%.2f', total_deposited)}"
    puts "Actual Live Portfolio:  $#{format('%.2f', current_equity)}"
    puts "SPY Portfolio Value:    $#{format('%.2f', spy_portfolio_value)}"
    puts ""
    puts "Live Profit:            $#{format('%.2f', live_profit)} (#{format('%.2f', live_pct)}%)"
    puts "SPY Profit:             $#{format('%.2f', spy_profit)} (#{format('%.2f', spy_pct)}%)"
    puts "-----------------------------------------------------"
    puts "Live vs SPY:            #{sign}$#{format('%.2f', diff)} (#{sign}#{format('%.2f', diff_pct)}%)"
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  end
end
