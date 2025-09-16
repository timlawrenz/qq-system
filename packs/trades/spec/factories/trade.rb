# frozen_string_literal: true

FactoryBot.define do
  factory :trade do
    algorithm
    symbol { 'AAPL' }
    executed_at { 1.hour.ago }
    side { 'buy' }
    quantity { 100.0 }
    price { 150.50 }
  end
end
