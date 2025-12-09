FactoryBot.define do
  factory :performance_snapshot do
    snapshot_date { Date.current }
    snapshot_type { 'weekly' }
    strategy_name { 'Enhanced Congressional' }
    total_equity { 100_000.00 }
    total_pnl { 0.00 }
    sharpe_ratio { nil }
    max_drawdown_pct { nil }
    volatility { nil }
    win_rate { nil }
    total_trades { 0 }
    winning_trades { 0 }
    losing_trades { 0 }
    calmar_ratio { nil }
    metadata { {} }

    trait :daily do
      snapshot_type { 'daily' }
    end

    trait :weekly do
      snapshot_type { 'weekly' }
    end

    trait :with_metrics do
      total_equity { 105_000.00 }
      total_pnl { 5000.00 }
      sharpe_ratio { 0.75 }
      max_drawdown_pct { -2.5 }
      volatility { 12.0 }
      win_rate { 65.0 }
      total_trades { 20 }
      winning_trades { 13 }
      losing_trades { 7 }
      calmar_ratio { 2.0 }
    end
  end
end
