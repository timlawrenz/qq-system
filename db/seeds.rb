# frozen_string_literal: true

# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# ---
# Setup: Create the Algorithm to test
# ---
algorithm = Algorithm.find_or_create_by!(id: 1) do |alg|
  alg.name = 'Simple Congressional Strategy'
  alg.description = 'A simple strategy that buys stocks based on recent congressional purchases.'
end
puts "Algorithm '#{algorithm.name}' is available."

# ---
# Step 1: Create the "cause" - the congressional trading signals.
# This is the data our algorithm would react to.
# ---
puts 'Creating prerequisite QuiverTrade signals...'
QuiverTrade.destroy_all
[
  { ticker: 'AAPL', transaction_type: 'Purchase', transaction_date: 40.days.ago, company: 'Apple Inc.', trader_name: 'A Trader' },
  { ticker: 'GOOGL', transaction_type: 'Purchase', transaction_date: 30.days.ago, company: 'Alphabet Inc.', trader_name: 'B Trader' },
  { ticker: 'MSFT', transaction_type: 'Purchase', transaction_date: 20.days.ago, company: 'Microsoft Corp.', trader_name: 'C Trader' },
  # This is a "Sale" and should be ignored by the simple strategy
  { ticker: 'TSLA', transaction_type: 'Sale', transaction_date: 15.days.ago, company: 'Tesla Inc.', trader_name: 'D Trader' }
].each do |trade|
  QuiverTrade.create!(trade)
end
puts "#{QuiverTrade.count} QuiverTrade signals created."

# ---
# Step 2: Create the "effect" - the trades our algorithm would have made.
# This simulates the execution of the strategy over time.
# ---
puts "Creating corresponding Trade records for '#{algorithm.name}'..."
Trade.where(algorithm: algorithm).destroy_all
[
  # Our algorithm sees the AAPL purchase and buys it.
  { symbol: 'AAPL', side: 'buy', quantity: 10, price: 150.00, executed_at: 39.days.ago },
  # It then sees the GOOGL purchase and buys it.
  { symbol: 'GOOGL', side: 'buy', quantity: 5, price: 2800.00, executed_at: 29.days.ago },
  # Finally, it sees the MSFT purchase and buys it.
  { symbol: 'MSFT', side: 'buy', quantity: 8, price: 300.00, executed_at: 19.days.ago }
].each do |trade_attrs|
  Trade.create!(trade_attrs.merge(algorithm: algorithm))
end
puts "#{Trade.count} sample trades created."

puts 'Seed data created successfully.'