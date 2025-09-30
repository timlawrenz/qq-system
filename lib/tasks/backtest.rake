# frozen_string_literal: true

namespace :backtest do
  desc "Run a historical backtest of the 'Simple' trading strategy over the last two years"
  task simple_strategy: :environment do
    puts 'Starting backtest of Simple Strategy...'

    # 1. Isolate Backtest Data
    # Create a dedicated algorithm record to associate with our simulated trades.
    # This keeps them separate from any live trading data.
    backtest_algorithm = Algorithm.create!(name: 'Simple Strategy Backtest', description: 'Backtest of Simple Strategy over last 2 years')
    puts "Using algorithm: '#{backtest_algorithm.name}' (ID: #{backtest_algorithm.id})"

    # 2. Define Backtest Parameters
    start_date = 2.years.ago.to_date
    end_date = Date.current
    initial_equity = 100_000.0 # Start with a hypothetical $100,000

    # For this simulation, we'll use a fixed equity amount for generating the target portfolio each day.
    # The performance_analysis pack will correctly calculate the portfolio's value curve based on the trades.
    current_equity = initial_equity

    puts "Backtest period: #{start_date} to #{end_date}"
    puts "Initial equity: $#{initial_equity}"

    # 3. Loop Through Each Day and Simulate Trades
    # This hash will hold the in-memory state of our simulated portfolio (symbol -> quantity)
    current_holdings = Hash.new(0.0)
    cash = initial_equity

    (start_date..end_date).each do |current_date|
      # The rebalancing logic will update our in-memory holdings based on the trades it creates
      current_holdings, cash = simulate_rebalancing(
        backtest_algorithm,
        result.target_positions,
        current_holdings,
        cash,
        current_date
      )

      # Calculate and display the total portfolio value for the current day
      holdings_value = current_holdings.sum { |symbol, qty| qty * (fetch_price(symbol, current_date) || 0.0) }
      total_value = holdings_value + cash
      print "\rProcessing #{current_date}... Holdings: #{current_holdings.size}, Portfolio Value: $#{format('%.2f', total_value)}"
    end

    puts "\nBacktest trade simulation complete."

    # 4. Trigger the Performance Analysis
    puts 'Initiating performance analysis...'
    analysis_result = InitiatePerformanceAnalysis.call(
      algorithm: backtest_algorithm,
      start_date: start_date,
      end_date: end_date
    )

    if analysis_result.success?
      analysis = analysis_result.analysis
      puts "Successfully enqueued analysis. ID: #{analysis.id}"
      puts 'The analysis will run in the background.'
      puts "To check status, run `rails c` and then `Analysis.find(#{analysis.id})`"
      puts "To view results when completed: `pp Analysis.find(#{analysis.id}).results`"
    else
      puts "Failed to enqueue analysis: #{analysis_result.errors.full_messages.join(', ')}"
    end
  end

  # Helper method for the simulation logic
  def simulate_rebalancing(algorithm, target_positions, current_holdings, cash, date)
    target_holdings = target_positions.each_with_object({}) do |pos, hash|
      hash[pos.symbol] = pos.target_value
    end

    # Combine all symbols from current and target portfolios to ensure we process all changes
    all_symbols = (current_holdings.keys | target_holdings.keys).uniq

    all_symbols.each do |symbol|
      price = fetch_price(symbol, date)
      next unless price # Skip if we can't get a price for the day (e.g., market closed)

      current_value = current_holdings[symbol].to_f * price
      target_value = target_holdings[symbol].to_f

      # Calculate the difference and determine if a trade is needed
      value_diff = target_value - current_value
      quantity_diff = value_diff / price

      # Only trade if the change is more than a tiny fraction to avoid noise
      next if quantity_diff.abs < 1e-6

      side = quantity_diff.positive? ? 'buy' : 'sell'
      trade_quantity = quantity_diff.abs.floor

      # Skip if quantity is zero after flooring
      next if trade_quantity.zero?

      # Use the CreateTrade command to create the trade record
      trade_result = CreateTrade.call(
        algorithm: algorithm,
        symbol: symbol,
        executed_at: date.end_of_day,
        side: side,
        quantity: trade_quantity,
        price: price
      )

      if trade_result.success?
        # Update our in-memory holdings state and cash balance
        trade_value = trade_quantity * price
        current_holdings[symbol] += (side == 'buy' ? trade_quantity : -trade_quantity)
        cash -= (side == 'buy' ? trade_value : -trade_value)
      else
        # Log error but continue the simulation
        puts "\nFailed to create trade for #{symbol} on #{date}: #{trade_result.errors.full_messages.join(', ')}"
      end
    end

    # Return the updated holdings and cash for the next iteration
    [current_holdings, cash]
  end

  def fetch_price(symbol, date)
    bar = HistoricalBar.for_symbol(symbol).where('DATE(timestamp) = ?', date).first
    bar&.close
  end
end
