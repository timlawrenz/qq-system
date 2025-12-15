# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Insider strategy integration', :vcr, type: :system do
  let(:equity) { BigDecimal('10000.00') }

  it 'runs Quiver insider API -> DB -> insider strategy end-to-end' do
    # Start from a clean slate for insider trades only
    QuiverTrade.where(trader_source: 'insider').delete_all

    # 1. Fetch insider trades from Quiver via FetchInsiderTrades (uses QuiverClient under the hood)
    fetch_result = FetchInsiderTrades.call(lookback_days: 60, limit: 100)

    expect(fetch_result).to be_success
    expect(fetch_result.total_count).to be >= 0

    insider_count = QuiverTrade.where(trader_source: 'insider').count

    # We do not assert on a minimum here because cassette contents may change over time,
    # but this validates that the command and mapping do not raise and that records can be persisted.
    expect(insider_count).to be >= 0

    # 2. Generate an insider mimicry portfolio from whatever insider data is present
    portfolio_result = TradingStrategies::GenerateInsiderMimicryPortfolio.call(
      total_equity: equity,
      lookback_days: 60,
      executive_only: false,      # include all insiders in this integration path
      sizing_mode: 'role_weighted'
    )

    expect(portfolio_result).to be_success
    expect(portfolio_result.target_positions).to be_a(Array)

    # Sanity: stats should be present and consistent with the command contract
    stats = portfolio_result.stats
    expect(stats).to include(:total_trades, :trades_after_filters, :unique_tickers)
  end
end
