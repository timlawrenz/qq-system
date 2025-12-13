# frozen_string_literal: true

# rubocop:disable RSpec/AnyInstance, RSpec/ExampleLength

require 'rails_helper'

RSpec.describe Trades::RebalanceToTarget do
  # Stub cancel_all_orders for all tests since it's called at the start of every rebalance
  before do
    allow_any_instance_of(AlpacaService).to receive(:cancel_all_orders).and_return(0)
  end

  let(:target_position_aapl) do
    TargetPosition.new(
      symbol: 'AAPL',
      asset_type: :stock,
      target_value: BigDecimal('1000')
    )
  end
  let(:target_position_googl) do
    TargetPosition.new(
      symbol: 'GOOGL',
      asset_type: :stock,
      target_value: BigDecimal('2000')
    )
  end
  let(:target_positions) { [target_position_aapl, target_position_googl] }

  describe 'validation' do
    it 'requires target parameter' do
      result = described_class.call

      expect(result).to be_failure
      expect(result.error.message).to include('missing keyword: :target')
    end

    it 'validates target is an array' do
      result = described_class.call(target: 'not_an_array')

      expect(result).to be_failure
      expect(result.error.message).to include('Target must be an array')
    end

    it 'validates target positions are TargetPosition objects' do
      result = described_class.call(target: ['not_a_target_position'])

      expect(result).to be_failure
      expect(result.error.message).to include('position at index 0 must be a TargetPosition object')
    end

    it 'raises NotImplementedError for non-stock asset types' do
      option_position = TargetPosition.new(
        symbol: 'AAPL',
        asset_type: :option,
        target_value: BigDecimal('500')
      )

      expect do
        described_class.call(target: [option_position])
      end.to raise_error(NotImplementedError, 'Asset type option is not supported. Only :stock is currently supported.')
    end

    it 'allows empty target array' do
      alpaca_service = instance_double(AlpacaService)
      allow(AlpacaService).to receive(:new).and_return(alpaca_service)
      allow(alpaca_service).to receive_messages(cancel_all_orders: 0, current_positions: [])

      result = described_class.call(target: [])

      expect(AlpacaService).to have_received(:new).twice
      expect(alpaca_service).to have_received(:current_positions)
      expect(result).to be_success
      expect(result.orders_placed).to eq([])
    end
  end

  describe 'successful execution' do
    let(:alpaca_service) { instance_double(AlpacaService) }
    let(:current_positions) do
      [
        {
          symbol: 'AAPL',
          qty: BigDecimal('10'),
          market_value: BigDecimal('1500'),
          side: 'long'
        },
        {
          symbol: 'MSFT',
          qty: BigDecimal('5'),
          market_value: BigDecimal('800'),
          side: 'long'
        }
      ]
    end

    let(:order_response) do
      {
        id: 'order_123',
        symbol: 'AAPL',
        side: 'sell',
        qty: BigDecimal('3.33'),
        status: 'accepted',
        submitted_at: Time.current
      }
    end

    before do
      allow(alpaca_service).to receive(:cancel_all_orders).and_return(0)
    end

    context 'with empty current portfolio' do
      it 'places buy orders for all target positions' do
        expect(AlpacaService).to receive(:new).exactly(4).times.and_return(alpaca_service)
        expect(alpaca_service).to receive(:current_positions).and_return([])
        expect(alpaca_service).to receive(:place_order).with(
          symbol: 'AAPL',
          side: 'buy',
          notional: BigDecimal('1000')
        ).and_return(order_response)
        expect(alpaca_service).to receive(:place_order).with(
          symbol: 'GOOGL',
          side: 'buy',
          notional: BigDecimal('2000')
        ).and_return(order_response)
        expect(AlpacaOrder).to receive(:create!).twice

        result = described_class.call(target: target_positions)

        expect(result).to be_success
        expect(result.orders_placed.size).to eq(2)
      end
    end

    context 'with existing positions not in target' do
      it 'places sell orders for positions not in target portfolio' do
        expect(AlpacaService).to receive(:new).exactly(5).times.and_return(alpaca_service)
        expect(alpaca_service).to receive(:current_positions).and_return(current_positions)

        # Sell order for MSFT (not in target) - uses close_position
        expect(alpaca_service).to receive(:close_position).with(
          symbol: 'MSFT'
        ).and_return(order_response)

        # Adjustment order for AAPL (reduce from $1500 to $1000)
        expect(alpaca_service).to receive(:place_order).with(
          symbol: 'AAPL',
          side: 'sell',
          notional: BigDecimal('500')
        ).and_return(order_response)

        # Buy order for GOOGL (new position)
        expect(alpaca_service).to receive(:place_order).with(
          symbol: 'GOOGL',
          side: 'buy',
          notional: BigDecimal('2000')
        ).and_return(order_response)

        expect(AlpacaOrder).to receive(:create!).exactly(3).times

        result = described_class.call(target: target_positions)

        expect(result).to be_success
        expect(result.orders_placed.size).to eq(3)
      end
    end

    context 'with positions matching target values' do
      let(:current_positions_matching) do
        [
          {
            symbol: 'AAPL',
            qty: BigDecimal('6.67'),
            market_value: BigDecimal('1000'),
            side: 'long'
          },
          {
            symbol: 'GOOGL',
            qty: BigDecimal('10'),
            market_value: BigDecimal('2000'),
            side: 'long'
          }
        ]
      end

      it 'does not place orders when current values match target (within tolerance)' do
        expect(AlpacaService).to receive(:new).twice.and_return(alpaca_service)
        expect(alpaca_service).to receive(:current_positions).and_return(current_positions_matching)

        result = described_class.call(target: target_positions)

        expect(result).to be_success
        expect(result.orders_placed).to be_empty
      end
    end

    context 'with positions requiring adjustments' do
      let(:current_positions_need_adjustment) do
        [
          {
            symbol: 'AAPL',
            qty: BigDecimal('13.33'),
            market_value: BigDecimal('2000'), # Need to sell $1000 worth
            side: 'long'
          },
          {
            symbol: 'GOOGL',
            qty: BigDecimal('5'),
            market_value: BigDecimal('1000'), # Need to buy $1000 worth
            side: 'long'
          }
        ]
      end

      it 'places adjustment orders to reach target values' do
        expect(AlpacaService).to receive(:new).exactly(4).times.and_return(alpaca_service)
        expect(alpaca_service).to receive(:current_positions).and_return(current_positions_need_adjustment)

        expect(alpaca_service).to receive(:place_order).with(
          symbol: 'AAPL',
          side: 'sell',
          notional: BigDecimal('1000')
        ).and_return(order_response)

        expect(alpaca_service).to receive(:place_order).with(
          symbol: 'GOOGL',
          side: 'buy',
          notional: BigDecimal('1000')
        ).and_return(order_response)

        expect(AlpacaOrder).to receive(:create!).twice

        result = described_class.call(target: target_positions)

        expect(result).to be_success
        expect(result.orders_placed.size).to eq(2)
      end
    end

    it 'creates AlpacaOrder records for each placed order' do
      expect(AlpacaService).to receive(:new).exactly(4).times.and_return(alpaca_service)
      expect(alpaca_service).to receive(:current_positions).and_return([])
      expect(alpaca_service).to receive(:place_order).twice.and_return(order_response)

      expect(AlpacaOrder).to receive(:create!).with(
        alpaca_order_id: 'order_123',
        symbol: 'AAPL',
        side: 'buy',
        status: 'accepted',
        qty: nil,
        notional: BigDecimal('1000'),
        order_type: 'market',
        time_in_force: 'day',
        submitted_at: order_response[:submitted_at]
      )

      expect(AlpacaOrder).to receive(:create!).with(
        alpaca_order_id: 'order_123',
        symbol: 'GOOGL',
        side: 'buy',
        status: 'accepted',
        qty: nil,
        notional: BigDecimal('2000'),
        order_type: 'market',
        time_in_force: 'day',
        submitted_at: order_response[:submitted_at]
      )

      described_class.call(target: target_positions)
    end
  end

  describe 'error handling' do
    let(:alpaca_service) { instance_double(AlpacaService) }

    before do
      allow(alpaca_service).to receive(:cancel_all_orders).and_return(0)
    end

    it 'fails when AlpacaService raises error for current_positions' do
      expect(AlpacaService).to receive(:new).twice.and_return(alpaca_service)
      expect(alpaca_service).to receive(:current_positions).and_raise(StandardError, 'API error')

      result = described_class.call(target: target_positions)

      expect(result).to be_failure
      expect(result.error.message).to include('Failed to fetch current positions: API error')
    end

    it 'fails when AlpacaService raises error for place_order' do
      expect(AlpacaService).to receive(:new).exactly(3).times.and_return(alpaca_service)
      expect(alpaca_service).to receive(:current_positions).and_return([])
      expect(alpaca_service).to receive(:place_order).and_raise(StandardError, 'Order failed')

      result = described_class.call(target: target_positions)

      expect(result).to be_failure
      expect(result.error.message).to include('Failed to place order for AAPL: Order failed')
    end

    it 'logs but does not fail when AlpacaOrder creation fails' do
      order_response = {
        id: 'order_123',
        symbol: 'AAPL',
        side: 'buy',
        qty: nil,
        status: 'accepted',
        submitted_at: Time.current
      }

      expect(AlpacaService).to receive(:new).exactly(3).times.and_return(alpaca_service)
      expect(alpaca_service).to receive(:current_positions).and_return([])
      expect(alpaca_service).to receive(:place_order).and_return(order_response)
      expect(AlpacaOrder).to receive(:create!).and_raise(StandardError, 'DB error')
      expect(Rails.logger).to receive(:error).with('Failed to create AlpacaOrder record: DB error')

      result = described_class.call(target: [target_position_aapl])

      expect(result).to be_success
    end

    # rubocop:disable RSpec/MultipleExpectations
    it 'skips orders for inactive assets and continues with other orders' do
      target_positions_test = [target_position_aapl, target_position_googl]

      expect(AlpacaService).to receive(:new).exactly(4).times.and_return(alpaca_service)
      expect(alpaca_service).to receive(:current_positions).and_return([])

      # First order fails due to inactive asset
      expect(alpaca_service).to receive(:place_order).with(
        symbol: 'AAPL',
        side: 'buy',
        notional: target_position_aapl.target_value
      ).and_raise(StandardError, 'Unable to place order: asset AAPL is not active')

      # Second order succeeds
      order_response = {
        id: 'order_456',
        symbol: 'GOOGL',
        side: 'buy',
        status: 'accepted',
        submitted_at: Time.current
      }
      expect(alpaca_service).to receive(:place_order).with(
        symbol: 'GOOGL',
        side: 'buy',
        notional: target_position_googl.target_value
      ).and_return(order_response)

      result = described_class.call(target: target_positions_test)

      expect(result).to be_success
      expect(result.orders_placed.size).to eq(2)

      # First order should be marked as skipped
      skipped_order = result.orders_placed.first
      expect(skipped_order[:symbol]).to eq('AAPL')
      expect(skipped_order[:status]).to eq('skipped')
      expect(skipped_order[:reason]).to eq('asset_not_active')

      # Second order should be successful
      successful_order = result.orders_placed.last
      expect(successful_order[:id]).to eq('order_456')
      expect(successful_order[:symbol]).to eq('GOOGL')

      # Verify AAPL was added to blocked assets
      expect(BlockedAsset.blocked_symbols).to include('AAPL')
    end
    # rubocop:enable RSpec/MultipleExpectations
  end

  describe 'order execution sequence' do
    let(:alpaca_service) { instance_double(AlpacaService) }
    let(:current_positions_with_unwanted) do
      [
        {
          symbol: 'MSFT',
          qty: BigDecimal('5'),
          market_value: BigDecimal('800'),
          side: 'long'
        }
      ]
    end

    before do
      allow(alpaca_service).to receive(:cancel_all_orders).and_return(0)
    end

    it 'executes sell orders before buy orders' do
      order_sequence = []

      expect(AlpacaService).to receive(:new).exactly(5).times.and_return(alpaca_service)
      expect(alpaca_service).to receive(:current_positions).and_return(current_positions_with_unwanted)

      # close_position is called for positions not in target
      expect(alpaca_service).to receive(:close_position).with(symbol: 'MSFT') do
        order_sequence << 'sell_MSFT'
        {
          id: 'order_123',
          symbol: 'MSFT',
          side: 'sell',
          status: 'accepted',
          submitted_at: Time.current
        }
      end

      # place_order is called for buying new positions
      expect(alpaca_service).to receive(:place_order) do |**args|
        order_sequence << "#{args[:side]}_#{args[:symbol]}"
        {
          id: 'order_123',
          symbol: args[:symbol],
          side: args[:side],
          status: 'accepted',
          submitted_at: Time.current
        }
      end.twice
      expect(AlpacaOrder).to receive(:create!).exactly(3).times

      described_class.call(target: target_positions)

      # Sell orders (positions not in target) should come first
      expect(order_sequence.first).to eq('sell_MSFT')
      # Then buy orders for target positions
      expect(order_sequence).to include('buy_AAPL', 'buy_GOOGL')
      # Ensure sell comes before buy
      sell_index = order_sequence.index('sell_MSFT')
      buy_aapl_index = order_sequence.index('buy_AAPL')
      buy_googl_index = order_sequence.index('buy_GOOGL')
      expect(sell_index).to be < buy_aapl_index
      expect(sell_index).to be < buy_googl_index
    end
  end
end
# rubocop:enable RSpec/AnyInstance, RSpec/ExampleLength
