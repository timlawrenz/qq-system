# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlpacaService, type: :service do
  let(:service) { described_class.new }
  let(:mock_client) { instance_double(Alpaca::Trade::Api::Client) }

  before do
    allow(Alpaca::Trade::Api::Client).to receive(:new).and_return(mock_client)
  end

  describe '#initialize' do
    it 'creates a new Alpaca Trade API client' do
      expect(Alpaca::Trade::Api::Client).to receive(:new)
      described_class.new
    end
  end

  describe '#account_equity' do
    let(:mock_account) { instance_double('Account', equity: '50000.75') }

    context 'when API call is successful' do
      before do
        allow(mock_client).to receive(:account).and_return(mock_account)
      end

      it 'returns account equity as BigDecimal' do
        result = service.account_equity

        expect(result).to eq(BigDecimal('50000.75'))
        expect(result).to be_a(BigDecimal)
      end

      it 'calls the Alpaca client account method' do
        expect(mock_client).to receive(:account)
        service.account_equity
      end
    end

    context 'when API call fails' do
      before do
        allow(mock_client).to receive(:account).and_raise(StandardError, 'API error')
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the error and raises a StandardError' do
        expect(Rails.logger).to receive(:error).with('Failed to get account equity: API error')

        expect { service.account_equity }.to raise_error(
          StandardError, 'Unable to retrieve account equity: API error'
        )
      end
    end
  end

  describe '#current_positions' do
    let(:mock_aapl_position) do
      instance_double('Position',
                      symbol: 'AAPL',
                      qty: '100.5',
                      market_value: '15000.25',
                      side: 'long')
    end

    let(:mock_googl_position) do
      instance_double('Position',
                      symbol: 'GOOGL',
                      qty: '50.0',
                      market_value: '12500.00',
                      side: 'short')
    end

    context 'when API call is successful' do
      before do
        allow(mock_client).to receive(:positions).and_return([mock_aapl_position, mock_googl_position])
      end

      it 'returns array of position hashes with BigDecimal values' do
        result = service.current_positions

        expect(result).to be_an(Array)
        expect(result.length).to eq(2)

        expect(result[0]).to eq(
          symbol: 'AAPL',
          qty: BigDecimal('100.5'),
          market_value: BigDecimal('15000.25'),
          side: 'long'
        )

        expect(result[1]).to eq(
          symbol: 'GOOGL',
          qty: BigDecimal('50.0'),
          market_value: BigDecimal('12500.00'),
          side: 'short'
        )
      end

      it 'calls the Alpaca client positions method' do
        expect(mock_client).to receive(:positions)
        service.current_positions
      end
    end

    context 'when no positions exist' do
      before do
        allow(mock_client).to receive(:positions).and_return([])
      end

      it 'returns empty array' do
        result = service.current_positions

        expect(result).to eq([])
      end
    end

    context 'when API call fails' do
      before do
        allow(mock_client).to receive(:positions).and_raise(StandardError, 'API error')
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the error and raises a StandardError' do
        expect(Rails.logger).to receive(:error).with('Failed to get current positions: API error')

        expect { service.current_positions }.to raise_error(
          StandardError, 'Unable to retrieve current positions: API error'
        )
      end
    end
  end

  describe '#place_order' do
    let(:mock_order) do
      instance_double('Order',
                      id: 'order-123',
                      symbol: 'AAPL',
                      side: 'buy',
                      qty: '100',
                      notional: nil,
                      status: 'filled',
                      submitted_at: '2024-01-15T10:30:00Z')
    end

    before do
      allow(Rails.logger).to receive(:info)
    end

    context 'with valid quantity order' do
      let(:order_params) do
        {
          symbol: 'aapl',
          side: 'buy',
          qty: BigDecimal('100')
        }
      end

      before do
        allow(mock_client).to receive(:new_order).and_return(mock_order)
      end

      it 'places the order successfully' do
        result = service.place_order(**order_params)

        expect(result).to eq(
          id: 'order-123',
          symbol: 'AAPL',
          side: 'buy',
          qty: BigDecimal('100'),
          notional: nil,
          status: 'filled',
          submitted_at: Time.zone.parse('2024-01-15T10:30:00Z')
        )
      end

      it 'calls Alpaca client with correct parameters' do
        expected_params = {
          symbol: 'AAPL',
          side: 'buy',
          type: 'market',
          time_in_force: 'day',
          qty: '100'
        }

        expect(mock_client).to receive(:new_order).with(**expected_params)
        service.place_order(**order_params)
      end

      it 'logs the order placement' do
        expected_log = 'Placing order: {symbol: "AAPL", side: "buy", type: "market", ' \
                       'time_in_force: "day", qty: "100"}'
        expect(Rails.logger).to receive(:info).with(expected_log)

        service.place_order(**order_params)
      end

      it 'normalizes symbol to uppercase' do
        expect(mock_client).to receive(:new_order).with(
          hash_including(symbol: 'AAPL')
        )
        service.place_order(**order_params)
      end

      it 'normalizes side to lowercase' do
        expect(mock_client).to receive(:new_order).with(
          hash_including(side: 'buy')
        )
        service.place_order(symbol: 'AAPL', side: 'BUY', qty: 100)
      end
    end

    context 'with valid notional order' do
      let(:mock_notional_order) do
        instance_double('Order',
                        id: 'order-456',
                        symbol: 'AAPL',
                        side: 'buy',
                        qty: nil,
                        notional: '1000.50',
                        status: 'pending',
                        submitted_at: '2024-01-15T10:30:00Z')
      end

      let(:order_params) do
        {
          symbol: 'AAPL',
          side: 'buy',
          notional: BigDecimal('1000.50')
        }
      end

      before do
        allow(mock_client).to receive(:new_order).and_return(mock_notional_order)
      end

      it 'places notional order successfully' do
        result = service.place_order(**order_params)

        expect(result).to eq(
          id: 'order-456',
          symbol: 'AAPL',
          side: 'buy',
          qty: nil,
          notional: BigDecimal('1000.50'),
          status: 'pending',
          submitted_at: Time.zone.parse('2024-01-15T10:30:00Z')
        )
      end

      it 'calls Alpaca client with notional parameter' do
        expected_params = {
          symbol: 'AAPL',
          side: 'buy',
          type: 'market',
          time_in_force: 'day',
          notional: '1000.5'
        }

        expect(mock_client).to receive(:new_order).with(**expected_params)
        service.place_order(**order_params)
      end
    end

    context 'with sell order' do
      let(:order_params) do
        {
          symbol: 'AAPL',
          side: 'sell',
          qty: 50
        }
      end

      before do
        allow(mock_client).to receive(:new_order).and_return(mock_order)
      end

      it 'places sell order successfully' do
        expect(mock_client).to receive(:new_order).with(
          hash_including(side: 'sell')
        )
        service.place_order(**order_params)
      end
    end

    context 'with invalid parameters' do
      it 'raises ArgumentError when symbol is missing' do
        expect { service.place_order(symbol: nil, side: 'buy', qty: 100) }.to raise_error(
          ArgumentError, 'Symbol is required'
        )
      end

      it 'raises ArgumentError when symbol is blank' do
        expect { service.place_order(symbol: '', side: 'buy', qty: 100) }.to raise_error(
          ArgumentError, 'Symbol is required'
        )
      end

      it 'raises ArgumentError when side is invalid' do
        expect { service.place_order(symbol: 'AAPL', side: 'invalid', qty: 100) }.to raise_error(
          ArgumentError, 'Side must be buy or sell'
        )
      end

      it 'raises ArgumentError when both notional and qty are missing' do
        expect { service.place_order(symbol: 'AAPL', side: 'buy') }.to raise_error(
          ArgumentError, 'Either notional or qty must be provided'
        )
      end

      it 'raises ArgumentError when both notional and qty are provided' do
        expect { service.place_order(symbol: 'AAPL', side: 'buy', notional: 1000, qty: 100) }.to raise_error(
          ArgumentError, 'Cannot specify both notional and qty'
        )
      end
    end

    context 'when order has nil timestamps' do
      let(:mock_order_no_timestamp) do
        instance_double('Order',
                        id: 'order-789',
                        symbol: 'AAPL',
                        side: 'buy',
                        qty: '100',
                        notional: nil,
                        status: 'pending',
                        submitted_at: nil)
      end

      before do
        allow(mock_client).to receive(:new_order).and_return(mock_order_no_timestamp)
      end

      it 'handles nil submitted_at gracefully' do
        result = service.place_order(symbol: 'AAPL', side: 'buy', qty: 100)

        expect(result[:submitted_at]).to be_nil
      end
    end

    context 'when API call fails' do
      before do
        allow(mock_client).to receive(:new_order).and_raise(StandardError, 'API error')
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the error and raises a StandardError' do
        expect(Rails.logger).to receive(:error).with('Failed to place order: API error')

        expect { service.place_order(symbol: 'AAPL', side: 'buy', qty: 100) }.to raise_error(
          StandardError, 'Unable to place order: API error'
        )
      end
    end

    context 'when ArgumentError occurs' do
      before do
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the validation error and re-raises ArgumentError' do
        expect(Rails.logger).to receive(:error).with('Invalid order parameters: Symbol is required')

        expect { service.place_order(symbol: nil, side: 'buy', qty: 100) }.to raise_error(
          ArgumentError, 'Symbol is required'
        )
      end
    end
  end
end
