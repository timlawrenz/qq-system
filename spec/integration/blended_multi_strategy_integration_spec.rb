# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Blended multi-strategy integration', type: :system do
  let(:account_equity) { BigDecimal('100000.00') }
  let(:alpaca_service) { instance_double(AlpacaService) }

  before do
    # Clean slate for relevant tables
    QuiverTrade.delete_all
    PoliticianProfile.delete_all

    # Stub AlpacaService so MasterAllocator/VolatilitySizingService do not hit real APIs
    allow(AlpacaService).to receive(:new).and_return(alpaca_service)

    allow(alpaca_service).to receive(:get_bars_multi).and_return({})
    allow(alpaca_service).to receive(:get_bars).and_return([
      { high: 110, low: 90, close: 100 }
    ])

    # Also stub Fetch (historical bar prewarm) to be a no-op success
    allow(Fetch).to receive(:call).and_return(
      double('FetchResult', failure?: false, api_errors: [], error: nil)
    )
  end

  it 'combines congressional and insider signals into a single blended portfolio' do
    # Seed congressional data
    PoliticianProfile.create!(
      name: 'Rep. Alpha',
      quality_score: 8.0,
      total_trades: 10,
      winning_trades: 7
    )

    QuiverTrade.create!(
      ticker: 'CONG',
      trader_name: 'Rep. Alpha',
      trader_source: 'congress',
      transaction_type: 'Purchase',
      transaction_date: 10.days.ago.to_date,
      trade_size_usd: '$30,000'
    )

    # Seed insider data
    QuiverTrade.create!(
      ticker: 'INSD',
      trader_name: 'CEO Insider',
      trader_source: 'insider',
      transaction_type: 'Purchase',
      transaction_date: 5.days.ago.to_date,
      trade_size_usd: '$50,000',
      relationship: 'CEO'
    )

    result = TradingStrategies::GenerateBlendedPortfolio.call(
      trading_mode: 'paper',
      total_equity: account_equity,
      config_override: {
        'strategies' => {
          # Explicitly disable lobbying for this test to focus on congressional + insider
          'lobbying' => { 'enabled' => false, 'weight' => 0.0 }
        }
      }
    )

    expect(result).to be_success

    positions = result.target_positions
    expect(positions).to be_an(Array)
    expect(positions).not_to be_empty

    strategy_results = result.strategy_results
    expect(strategy_results.keys).to include('congressional', 'insider')
    expect(strategy_results['congressional'][:signal_count]).to be > 0
    expect(strategy_results['insider'][:signal_count]).to be > 0
  end
end
