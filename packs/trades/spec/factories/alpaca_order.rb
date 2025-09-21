# frozen_string_literal: true

FactoryBot.define do
  factory :alpaca_order do
    alpaca_order_id { SecureRandom.uuid }
    quiver_trade { nil } # optional association
    symbol { 'AAPL' }
    side { 'buy' }
    status { 'filled' }
    qty { 100.0 }
    notional { 15_000.0 }
    order_type { 'market' }
    time_in_force { 'day' }
    submitted_at { 1.hour.ago }
    filled_at { 30.minutes.ago }
    filled_avg_price { 150.50 }

    trait :with_quiver_trade do
      quiver_trade
    end

    trait :pending do
      status { 'pending' }
      filled_at { nil }
      filled_avg_price { nil }
    end

    trait :cancelled do
      status { 'cancelled' }
      filled_at { nil }
      filled_avg_price { nil }
    end

    trait :sell_order do
      side { 'sell' }
    end
  end
end
