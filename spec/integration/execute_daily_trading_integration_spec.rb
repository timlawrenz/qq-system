# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Workflows::ExecuteDailyTrading, type: :system do
  let(:alpaca_service) { instance_double(AlpacaService) }
  let(:account_equity) { BigDecimal('100000.00') }
  let(:existing_positions) { [] }

  before do
    # Mock Alpaca Service
    allow(AlpacaService).to receive(:new).and_return(alpaca_service)
    allow(alpaca_service).to receive_messages(account_equity: account_equity, current_positions: existing_positions,
                                              get_bars: [], get_bars_multi: {}, cancel_all_orders: 0)

    # Mock Quiver Data (empty by default)
    allow(QuiverTrade).to receive(:where).and_call_original
  end

  it 'executes the full workflow successfully with no signals' do
    # Expect no trades to be placed if no signals
    expect(alpaca_service).not_to receive(:place_order)

    # If we have no positions, close_position shouldn't be called
    expect(alpaca_service).not_to receive(:close_position)

    result = described_class.call(
      trading_mode: 'paper',
      skip_data_fetch: true,
      skip_politician_scoring: true
    )

    expect(result).to be_success
    expect(result.target_positions).to be_empty
    expect(result.orders_placed).to be_empty
  end

  context 'with existing positions and no signals' do
    let(:existing_positions) do
      [
        { symbol: 'AAPL', qty: 10, market_value: 1500.0, side: 'long' }
      ]
    end

    it 'liquidates existing positions' do
      expect(alpaca_service).to receive(:close_position)
        .with(symbol: 'AAPL')
        .and_return({ status: 'filled', symbol: 'AAPL', side: 'sell' })

      result = described_class.call(
        trading_mode: 'paper',
        skip_data_fetch: true,
        skip_politician_scoring: true
      )

      expect(result).to be_success
      expect(result.orders_placed.size).to eq(1)
      expect(result.orders_placed.first[:side]).to eq('sell')
    end
  end

  context 'with valid signals' do
    before do
      # Create a mock congressional trade
      create(:quiver_trade,
             ticker: 'MSFT',
             transaction_type: 'Purchase',
             trader_source: 'congress',
             transaction_date: 2.days.ago)

      # Mock price data for sizing
      allow(alpaca_service).to receive(:get_bars).with('MSFT', any_args).and_return([
                                                                                      { high: 105, low: 95, close: 100,
                                                                                        timestamp: 1.day.ago }
                                                                                    ])
    end

    it 'generates target positions and places orders' do
      # Expect a buy order for MSFT
      expect(alpaca_service).to receive(:place_order)
        .with(hash_including(symbol: 'MSFT', side: 'buy'))
        .and_return({ status: 'filled', symbol: 'MSFT' })

      result = described_class.call(
        trading_mode: 'paper',
        skip_data_fetch: true, # Use the DB record we created
        skip_politician_scoring: true
      )

      expect(result).to be_success
      expect(result.target_positions).not_to be_empty
      expect(result.target_positions.first.symbol).to eq('MSFT')
    end
  end
end
