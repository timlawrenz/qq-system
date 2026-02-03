# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Blended conflict-free integration', type: :system do
  let(:account_equity) { BigDecimal('100000.00') }
  let(:alpaca_service) { instance_double(AlpacaService) }

  before do
    # Clean slate for relevant tables
    QuiverTrade.delete_all
    PoliticianProfile.delete_all

    # Stub AlpacaService so MasterAllocator/VolatilitySizingService do not hit real APIs
    allow(AlpacaService).to receive(:new).and_return(alpaca_service)

    allow(alpaca_service).to receive_messages(get_bars_multi: {}, get_bars: [
                                                { high: 110, low: 90, close: 100 }
                                              ])

    # Also stub Fetch (historical bar prewarm) to be a no-op success
    allow(Fetch).to receive(:call).and_return(
      double('FetchResult', failure?: false, api_errors: [], error: nil)
    )
  end

  it 'nets overlapping congressional and insider signals into a single position per ticker' do
    # Seed overlapping ticker for both congressional and insider strategies
    PoliticianProfile.create!(
      name: 'Rep. Overlap',
      quality_score: 8.5,
      total_trades: 20,
      winning_trades: 15
    )

    QuiverTrade.create!(
      ticker: 'OVER',
      trader_name: 'Rep. Overlap',
      trader_source: 'congress',
      transaction_type: 'Purchase',
      transaction_date: 10.days.ago.to_date,
      trade_size_usd: '$40,000'
    )

    QuiverTrade.create!(
      ticker: 'OVER',
      trader_name: 'CEO Overlap',
      trader_source: 'insider',
      transaction_type: 'Purchase',
      transaction_date: 5.days.ago.to_date,
      trade_size_usd: '$60,000',
      relationship: 'CEO'
    )

    result = TradingStrategies::GenerateBlendedPortfolio.call(
      trading_mode: 'paper',
      total_equity: account_equity,
      config_override: {
        'strategies' => {
          # Ensure both strategies are enabled and contributing
          'congressional' => { 'enabled' => true, 'weight' => 0.5 },
          'insider' => { 'enabled' => true, 'weight' => 0.5 },
          # Disable lobbying to focus this spec
          'lobbying' => { 'enabled' => false, 'weight' => 0.0 }
        }
      }
    )

    expect(result).to be_success

    positions = result.target_positions
    expect(positions).to be_an(Array)
    expect(positions).not_to be_empty

    # There should be exactly one blended position for the overlapping ticker
    over_positions = positions.select { |p| p.symbol == 'OVER' }
    expect(over_positions.size).to eq(1)
    expect(over_positions.first.target_value).not_to eq(0)

    # And there should be no duplicate symbols overall (conflict-free netting)
    symbol_counts = positions.map(&:symbol).tally
    expect(symbol_counts.values.max).to eq(1)

    # Both strategies should report non-zero signal counts
    strategy_results = result.strategy_results
    expect(strategy_results.keys).to include('congressional', 'insider')
    expect(strategy_results['congressional'][:signal_count]).to be > 0
    expect(strategy_results['insider'][:signal_count]).to be > 0
  end
end
