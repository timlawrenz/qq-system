# frozen_string_literal: true

FactoryBot.define do
  factory :quiver_trade do
    ticker { 'AAPL' }
    company { 'Apple Inc.' }
    trader_name { 'John Doe' }
    trader_source { 'congress' }
    transaction_date { Date.current }
    transaction_type { 'Purchase' }
    trade_size_usd { '$1,000 - $15,000' }
    disclosed_at { Time.current }

    # Insider-specific defaults (nil by default to keep factory generic)
    relationship { nil }
    shares_held { nil }
    ownership_percent { nil }
    trade_type { nil }
  end
end
