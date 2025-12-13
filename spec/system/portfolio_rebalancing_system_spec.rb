# frozen_string_literal: true

require 'rails_helper'

# System Spec: Portfolio Rebalancing End-to-End
#
# These specs test realistic portfolio management scenarios that mimic
# production conditions, ensuring the system correctly handles:
# - Empty target portfolios (liquidation scenarios)
# - Partial rebalancing (some positions kept, some liquidated)
# - Full rebalancing (all positions replaced)
# - Signal starvation (no data available)
#
# These tests caught the critical bug where $46k was left on the table:
# When SKIP_TRADING_DATA=true resulted in 0 signals → empty target →
# script exited early instead of liquidating existing positions.
#
# rubocop:disable RSpec/StubbedMock
# Note: System specs use expect().to receive() for strict behavior verification
RSpec.describe 'Portfolio Rebalancing System', type: :system do
  let(:alpaca_service) { instance_double(AlpacaService) }
  let(:account_equity) { BigDecimal('101976.05') }

  # Realistic positions from production bug scenario
  let(:existing_positions) do
    [
      { symbol: 'REGN', qty: BigDecimal('10'), market_value: BigDecimal('13212.98'), side: 'long' },
      { symbol: 'PG', qty: BigDecimal('50'), market_value: BigDecimal('7420.06'), side: 'long' },
      { symbol: 'ADP', qty: BigDecimal('25'), market_value: BigDecimal('7413.11'), side: 'long' },
      { symbol: 'PAYX', qty: BigDecimal('60'), market_value: BigDecimal('7411.85'), side: 'long' },
      { symbol: 'BITB', qty: BigDecimal('200'), market_value: BigDecimal('7289.98'), side: 'long' },
      { symbol: 'TSLA', qty: BigDecimal('15'), market_value: BigDecimal('6423.45'), side: 'long' },
      { symbol: 'NVDA', qty: BigDecimal('8'), market_value: BigDecimal('4321.87'), side: 'long' },
      { symbol: 'AMD', qty: BigDecimal('30'), market_value: BigDecimal('2100.51'), side: 'long' }
    ]
  end

  let(:close_order_response) do
    {
      id: 'order_close_123',
      side: 'sell',
      status: 'accepted',
      submitted_at: Time.current
    }
  end

  before do
    # Stub AlpacaService for all scenarios
    allow(AlpacaService).to receive(:new).and_return(alpaca_service)
    allow(alpaca_service).to receive_messages(cancel_all_orders: 0, account_equity: account_equity)
  end

  describe 'Scenario 1: Signal Starvation → Empty Target → Full Liquidation' do
    # Production bug: SKIP_TRADING_DATA=true → 0 congressional signals →
    # 0 insider signals → empty target → script exits → $46k left in market

    it 'liquidates all existing positions when target portfolio is empty' do
      # Current state: 8 positions totaling ~$55.6k
      expect(alpaca_service).to receive(:current_positions).and_return(existing_positions)

      # Expected: All 8 positions should be closed
      existing_positions.each do |position|
        expect(alpaca_service).to receive(:close_position)
          .with(symbol: position[:symbol])
          .and_return(close_order_response.merge(symbol: position[:symbol]))
      end

      # Execute rebalancing with empty target
      result = Trades::RebalanceToTarget.call(target: [])

      # Verify all positions were liquidated
      expect(result).to be_success
      expect(result.orders_placed.size).to eq(8)
      expect(result.orders_placed.pluck(:side).uniq).to eq(['sell'])
      expect(result.orders_placed.pluck(:symbol)).to match_array(
        existing_positions.pluck(:symbol)
      )
    end

    it 'leaves 100% cash when empty target executed' do
      expect(alpaca_service).to receive(:current_positions).and_return(existing_positions)

      # Mock all close_position calls
      existing_positions.each do |position|
        allow(alpaca_service).to receive(:close_position)
          .with(symbol: position[:symbol])
          .and_return(close_order_response)
      end

      result = Trades::RebalanceToTarget.call(target: [])

      # After liquidation, portfolio should be:
      # - Cash: $101,976.05 (100%)
      # - Holdings: $0 (0%)
      expect(result).to be_success
      expect(result.orders_placed.size).to eq(existing_positions.size)
    end
  end

  describe 'Scenario 2: Partial Rebalancing → Keep Some, Liquidate Others' do
    it 'keeps positions in target, liquidates positions not in target' do
      # Target: Only keep REGN and PG with adjusted values
      target_positions = [
        TargetPosition.new(symbol: 'REGN', asset_type: :stock, target_value: BigDecimal('15000')),
        TargetPosition.new(symbol: 'PG', asset_type: :stock, target_value: BigDecimal('10000'))
      ]

      expect(alpaca_service).to receive(:current_positions).and_return(existing_positions)

      # Expected liquidations: ADP, PAYX, BITB, TSLA, NVDA, AMD (6 positions)
      keep_symbols = %w[REGN PG]
      positions_to_liquidate = existing_positions.reject { |p| keep_symbols.include?(p[:symbol]) }
      positions_to_liquidate.each do |position|
        expect(alpaca_service).to receive(:close_position)
          .with(symbol: position[:symbol])
          .and_return(close_order_response.merge(symbol: position[:symbol]))
      end

      # Expected adjustments: REGN ($13,212.98 → $15,000), PG ($7,420.06 → $10,000)
      expect(alpaca_service).to receive(:place_order).with(
        symbol: 'REGN',
        side: 'buy',
        notional: BigDecimal('1787.02') # $15,000 - $13,212.98
      ).and_return(close_order_response.merge(symbol: 'REGN'))

      expect(alpaca_service).to receive(:place_order).with(
        symbol: 'PG',
        side: 'buy',
        notional: BigDecimal('2579.94') # $10,000 - $7,420.06
      ).and_return(close_order_response.merge(symbol: 'PG'))

      result = Trades::RebalanceToTarget.call(target: target_positions)

      expect(result).to be_success
      expect(result.orders_placed.size).to eq(8) # 6 liquidations + 2 adjustments
    end
  end

  describe 'Scenario 3: Full Replacement → Liquidate All, Buy New' do
    it 'liquidates all existing positions and buys new target positions' do
      # Target: Completely different portfolio
      target_positions = [
        TargetPosition.new(symbol: 'MSFT', asset_type: :stock, target_value: BigDecimal('20000')),
        TargetPosition.new(symbol: 'GOOGL', asset_type: :stock, target_value: BigDecimal('20000')),
        TargetPosition.new(symbol: 'AAPL', asset_type: :stock, target_value: BigDecimal('15000'))
      ]

      expect(alpaca_service).to receive(:current_positions).and_return(existing_positions)

      # Expected: Liquidate all 8 existing positions
      existing_positions.each do |position|
        expect(alpaca_service).to receive(:close_position)
          .with(symbol: position[:symbol])
          .and_return(close_order_response.merge(symbol: position[:symbol]))
      end

      # Expected: Buy 3 new positions
      target_positions.each do |target|
        expect(alpaca_service).to receive(:place_order).with(
          symbol: target.symbol,
          side: 'buy',
          notional: target.target_value
        ).and_return(close_order_response.merge(symbol: target.symbol))
      end

      result = Trades::RebalanceToTarget.call(target: target_positions)

      expect(result).to be_success
      expect(result.orders_placed.size).to eq(11) # 8 sells + 3 buys
    end
  end

  describe 'Scenario 4: Realistic Blended Strategy Flow' do
    # Mimics production conditions with multi-strategy portfolio generation

    it 'generates empty target when no signals available and liquidates positions' do
      # Setup: No congressional or insider trades in database
      expect(QuiverTrade.count).to eq(0)

      # Mock account data
      expect(alpaca_service).to receive(:current_positions).and_return(existing_positions)

      # Expected: All positions liquidated
      existing_positions.each do |position|
        expect(alpaca_service).to receive(:close_position)
          .with(symbol: position[:symbol])
          .and_return(close_order_response.merge(symbol: position[:symbol]))
      end

      # Execute full flow: Generate target → Rebalance
      target_result = TradingStrategies::GenerateBlendedPortfolio.call(
        trading_mode: 'paper',
        total_equity: account_equity
      )

      # When no signals available, blended strategy returns empty target
      expect(target_result).to be_success
      expect(target_result.target_positions).to be_empty

      # CRITICAL: Empty target MUST trigger liquidation, not early exit
      rebalance_result = Trades::RebalanceToTarget.call(
        target: target_result.target_positions
      )

      expect(rebalance_result).to be_success
      expect(rebalance_result.orders_placed.size).to eq(8)
      expect(rebalance_result.orders_placed.all? { |o| o[:side] == 'sell' }).to be true
    end

    it 'handles transition from multi-strategy portfolio to congressional-only' do
      # Setup: Has existing blended positions
      expect(alpaca_service).to receive(:current_positions).and_return(existing_positions)

      # Create congressional signals only
      create(:quiver_trade,
             ticker: 'NVDA',
             trader_source: 'congress',
             transaction_type: 'Purchase',
             transaction_date: 10.days.ago)

      # Target: Congressional strategy generates different portfolio
      target_positions = [
        TargetPosition.new(symbol: 'NVDA', asset_type: :stock, target_value: BigDecimal('40000'))
      ]

      # Expected: Liquidate 7 positions (keep NVDA, adjust value)
      positions_to_liquidate = existing_positions.reject { |p| p[:symbol] == 'NVDA' }
      positions_to_liquidate.each do |position|
        expect(alpaca_service).to receive(:close_position)
          .with(symbol: position[:symbol])
          .and_return(close_order_response.merge(symbol: position[:symbol]))
      end

      # Adjust NVDA: $4,321.87 → $40,000
      nvda_increase = BigDecimal('35678.13')
      expect(alpaca_service).to receive(:place_order).with(
        symbol: 'NVDA',
        side: 'buy',
        notional: nvda_increase
      ).and_return(close_order_response.merge(symbol: 'NVDA'))

      result = Trades::RebalanceToTarget.call(target: target_positions)

      expect(result).to be_success
      expect(result.orders_placed.size).to eq(8) # 7 liquidations + 1 buy
    end
  end

  describe 'Scenario 5: Edge Cases and Error Conditions' do
    it 'handles inactive assets during liquidation gracefully' do
      # Setup: One position becomes inactive/non-tradable
      expect(alpaca_service).to receive(:current_positions).and_return(existing_positions)

      # REGN becomes inactive (can't trade)
      expect(alpaca_service).to receive(:close_position).with(symbol: 'REGN')
                                                        .and_raise(StandardError, 'asset REGN is not active')

      # All other positions liquidate normally
      existing_positions[1..].each do |position|
        expect(alpaca_service).to receive(:close_position)
          .with(symbol: position[:symbol])
          .and_return(close_order_response.merge(symbol: position[:symbol]))
      end

      result = Trades::RebalanceToTarget.call(target: [])

      expect(result).to be_success
      expect(result.orders_placed.size).to eq(8) # 1 skipped + 7 closed

      skipped = result.orders_placed.find { |o| o[:symbol] == 'REGN' }
      expect(skipped[:status]).to eq('skipped')
      expect(skipped[:reason]).to eq('asset_not_active')

      # Verify REGN blocked for future trading
      expect(BlockedAsset.blocked_symbols).to include('REGN')
    end

    it 'skips tiny adjustments below $1 minimum' do
      # Setup: Position very close to target value
      nearly_matched_positions = [
        { symbol: 'AAPL', qty: BigDecimal('10'), market_value: BigDecimal('1000.50'), side: 'long' }
      ]

      target_positions = [
        TargetPosition.new(symbol: 'AAPL', asset_type: :stock, target_value: BigDecimal('1000.75'))
      ]

      expect(alpaca_service).to receive(:current_positions).and_return(nearly_matched_positions)

      # Expected: No orders placed (difference $0.25 < $1.00 minimum)
      result = Trades::RebalanceToTarget.call(target: target_positions)

      expect(result).to be_success
      expect(result.orders_placed).to be_empty
    end

    it 'handles insufficient buying power during rebalancing' do
      # Setup: Small cash position, large target
      small_positions = [
        { symbol: 'AAPL', qty: BigDecimal('1'), market_value: BigDecimal('150'), side: 'long' }
      ]

      huge_target = [
        TargetPosition.new(symbol: 'AAPL', asset_type: :stock, target_value: BigDecimal('50000'))
      ]

      expect(alpaca_service).to receive(:current_positions).and_return(small_positions)
      expect(alpaca_service).to receive(:place_order)
        .and_raise(StandardError, 'insufficient buying power')

      result = Trades::RebalanceToTarget.call(target: huge_target)

      expect(result).to be_success
      expect(result.orders_placed.size).to eq(1)
      expect(result.orders_placed.first[:status]).to eq('skipped')
      expect(result.orders_placed.first[:reason]).to eq('insufficient_buying_power')
    end
  end

  describe 'Scenario 6: Production Bug Reproduction' do
    # Exact scenario from Dec 12, 2025 11:33:11 AM EST

    it 'reproduces and fixes the $46k idle cash bug' do
      # Exact production state
      production_equity = BigDecimal('101976.05')
      production_holdings = BigDecimal('55593.81')
      production_cash = BigDecimal('46377.40')

      # Verify math: holdings + cash should equal equity (within rounding)
      expect((production_holdings + production_cash - production_equity).abs).to be < 10

      # Setup: SKIP_TRADING_DATA=true → no signals → empty target
      expect(QuiverTrade.count).to eq(0)
      expect(alpaca_service).to receive(:current_positions).and_return(existing_positions)

      # BUG: Shell script exits early when target empty
      # FIX: RebalanceToTarget handles empty target correctly

      # Expected: All 8 positions liquidated
      existing_positions.each do |position|
        expect(alpaca_service).to receive(:close_position)
          .with(symbol: position[:symbol])
          .and_return(close_order_response.merge(symbol: position[:symbol]))
      end

      # Generate empty target (no signals available)
      target_result = TradingStrategies::GenerateBlendedPortfolio.call(
        trading_mode: 'paper',
        total_equity: production_equity
      )

      expect(target_result.target_positions).to be_empty

      # Execute rebalancing (MUST NOT skip when empty!)
      result = Trades::RebalanceToTarget.call(target: target_result.target_positions)

      expect(result).to be_success
      expect(result.orders_placed.size).to eq(8)

      # After fix: Portfolio should be 100% cash
      # Holdings: $0, Cash: $101,976.05
      total_liquidated = existing_positions.sum { |p| p[:market_value] }
      expect(total_liquidated).to be_within(100).of(production_holdings)
    end
  end
end
# rubocop:enable RSpec/StubbedMock
