# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingDashboard::FetchTradingDashboardSnapshot do
  before do
    Rails.cache.clear
  end

  it 'returns empty state when no snapshots exist' do
    result = described_class.call

    expect(result.success?).to be(true)
    expect(result.metrics[:state]).to eq('empty')
  end

  it 'caches metrics for 30 seconds (does not hit PerformanceSnapshot on second call)' do
    store = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(store)

    create(
      :performance_snapshot,
      snapshot_date: Date.current,
      total_equity: 100_000,
      metadata: {
        'snapshot_captured_at' => Time.current.iso8601,
        'account' => {
          'cash' => 10_000,
          'invested' => 90_000,
          'cash_pct' => 10.0,
          'invested_pct' => 90.0,
          'position_count' => 1
        },
        'positions' => [
          { 'symbol' => 'AAPL', 'side' => 'long', 'qty' => 1, 'market_value' => 90_000 }
        ],
        'risk' => {
          'concentration_pct' => 90.0,
          'concentration_symbol' => 'AAPL'
        }
      }
    )

    described_class.call

    expect(PerformanceSnapshot).not_to receive(:all)
    expect(PerformanceSnapshot).not_to receive(:where)
    expect(PerformanceSnapshot).not_to receive(:order)

    described_class.call
  end
end
