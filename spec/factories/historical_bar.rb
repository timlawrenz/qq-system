# frozen_string_literal: true

FactoryBot.define do
  factory :historical_bar do
    symbol { 'AAPL' }
    timestamp { Date.current }
    open { BigDecimal('150.0') }
    high { BigDecimal('155.0') }
    low { BigDecimal('145.0') }
    close { BigDecimal('152.0') }
    volume { 1000 }
  end
end
