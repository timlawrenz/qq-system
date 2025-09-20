# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UpdateTrade, type: :command do
  let(:algorithm) { create(:algorithm) }
  let(:trade) { create(:trade, algorithm: algorithm) }

  describe 'successful updates' do
    it 'updates symbol' do
      result = described_class.call(trade: trade, symbol: 'MSFT')

      expect(result).to be_success
      expect(result.trade.symbol).to eq('MSFT')
    end

    it 'normalizes symbol to uppercase' do
      result = described_class.call(trade: trade, symbol: 'msft')

      expect(result).to be_success
      expect(result.trade.symbol).to eq('MSFT')
    end

    it 'updates side' do
      result = described_class.call(trade: trade, side: 'sell')

      expect(result).to be_success
      expect(result.trade.side).to eq('sell')
    end

    it 'normalizes side to lowercase' do
      result = described_class.call(trade: trade, side: 'SELL')

      expect(result).to be_success
      expect(result.trade.side).to eq('sell')
    end

    it 'updates quantity' do
      result = described_class.call(trade: trade, quantity: 200)

      expect(result).to be_success
      expect(result.trade.quantity).to eq(200.0)
    end

    it 'updates price' do
      result = described_class.call(trade: trade, price: 175.25)

      expect(result).to be_success
      expect(result.trade.price).to eq(175.25)
    end

    it 'updates executed_at' do
      new_time = '2024-02-15T14:30:00Z'
      result = described_class.call(trade: trade, executed_at: new_time)

      expect(result).to be_success
      expect(result.trade.executed_at).to eq(DateTime.parse(new_time))
    end

    it 'updates multiple attributes at once' do
      result = described_class.call(
        trade: trade,
        symbol: 'GOOGL',
        side: 'sell',
        quantity: 50,
        price: 2800.00
      )

      expect(result).to be_success
      expect(result.trade.symbol).to eq('GOOGL')
      expect(result.trade.side).to eq('sell')
      expect(result.trade.quantity).to eq(50.0)
      expect(result.trade.price).to eq(2800.00)
    end

    it 'does nothing when no attributes are provided' do
      original_symbol = trade.symbol
      original_updated_at = trade.updated_at

      result = described_class.call(trade: trade)

      expect(result).to be_success
      expect(result.trade.symbol).to eq(original_symbol)
      expect(result.trade.updated_at).to eq(original_updated_at)
    end

    it 'converts string quantities and prices to float' do
      result = described_class.call(trade: trade, quantity: '75', price: '125.75')

      expect(result).to be_success
      expect(result.trade.quantity).to eq(75.0)
      expect(result.trade.price).to eq(125.75)
    end
  end

  describe 'validation failures' do
    it 'fails when side is invalid' do
      result = described_class.call(trade: trade, side: 'invalid')

      expect(result).to be_failure
      expect(result.error.message).to include('Side must be buy or sell')
    end

    it 'fails when quantity is zero' do
      result = described_class.call(trade: trade, quantity: 0)

      expect(result).to be_failure
      expect(result.error.message).to include('Quantity must be greater than 0')
    end

    it 'fails when quantity is negative' do
      result = described_class.call(trade: trade, quantity: -10)

      expect(result).to be_failure
      expect(result.error.message).to include('Quantity must be greater than 0')
    end

    it 'fails when price is zero' do
      result = described_class.call(trade: trade, price: 0)

      expect(result).to be_failure
      expect(result.error.message).to include('Price must be greater than 0')
    end

    it 'fails when price is negative' do
      result = described_class.call(trade: trade, price: -50)

      expect(result).to be_failure
      expect(result.error.message).to include('Price must be greater than 0')
    end

    it 'fails when executed_at is invalid' do
      result = described_class.call(trade: trade, executed_at: 'invalid-date')

      expect(result).to be_failure
      expect(result.error.message).to include('Executed at invalid date/time format: invalid date')
    end

    it 'fails when trade is missing' do
      result = described_class.call(symbol: 'AAPL')

      expect(result).to be_failure
    end
  end
end
