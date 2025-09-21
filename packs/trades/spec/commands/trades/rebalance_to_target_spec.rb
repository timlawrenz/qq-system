# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trades::RebalanceToTarget, type: :command do
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
      alpaca_service = double('AlpacaService')
      expect(AlpacaService).to receive(:new).and_return(alpaca_service)
      expect(alpaca_service).to receive(:current_positions).and_return([])

      result = described_class.call(target: [])

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

    context 'with empty current portfolio' do
      it 'places buy orders for all target positions' do
        expect(AlpacaService).to receive(:new).exactly(3).times.and_return(alpaca_service)
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
  end
end
