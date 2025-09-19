# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreateTrade, type: :command do
  let(:algorithm) { create(:algorithm) }
  let(:valid_params) do
    {
      algorithm: algorithm,
      symbol: 'AAPL',
      executed_at: '2024-01-15T10:30:00Z',
      side: 'buy',
      quantity: 100,
      price: 150.50
    }
  end

  describe 'successful creation' do
    it 'creates a trade with valid parameters' do
      result = described_class.call(**valid_params)

      expect(result).to be_success
      expect(result.trade).to be_persisted
      expect(result.trade.algorithm).to eq(algorithm)
      expect(result.trade.symbol).to eq('AAPL')
      expect(result.trade.side).to eq('buy')
      expect(result.trade.quantity).to eq(100.0)
      expect(result.trade.price).to eq(150.50)
    end

    it 'normalizes symbol to uppercase' do
      result = described_class.call(**valid_params, symbol: 'aapl')

      expect(result).to be_success
      expect(result.trade.symbol).to eq('AAPL')
    end

    it 'normalizes side to lowercase' do
      result = described_class.call(**valid_params, side: 'BUY')

      expect(result).to be_success
      expect(result.trade.side).to eq('buy')
    end

    it 'converts string quantities and prices to float' do
      result = described_class.call(**valid_params, quantity: '100', price: '150.50')

      expect(result).to be_success
      expect(result.trade.quantity).to eq(100.0)
      expect(result.trade.price).to eq(150.50)
    end

    it 'accepts DateTime objects for executed_at' do
      executed_at = DateTime.new(2024, 1, 15, 10, 30, 0)
      result = described_class.call(**valid_params, executed_at: executed_at)

      expect(result).to be_success
      expect(result.trade.executed_at).to eq(executed_at)
    end

    it 'accepts Time objects for executed_at' do
      executed_at = Time.zone.parse('2024-01-15 10:30:00')
      result = described_class.call(**valid_params, executed_at: executed_at)

      expect(result).to be_success
      expect(result.trade.executed_at).to eq(executed_at)
    end
  end

  describe 'validation failures' do
    it 'fails when symbol is missing' do
      result = described_class.call(**valid_params.except(:symbol))

      expect(result).to be_failure
      expect(result.error.message).to include('missing keyword: :symbol')
    end

    it 'fails when side is invalid' do
      result = described_class.call(**valid_params, side: 'invalid')

      expect(result).to be_failure
      expect(result.error.message).to include('Side is not included in the list')
    end

    it 'fails when quantity is zero' do
      result = described_class.call(**valid_params, quantity: 0)

      expect(result).to be_failure
      expect(result.error.message).to include('Quantity must be greater than 0')
    end

    it 'fails when quantity is negative' do
      result = described_class.call(**valid_params, quantity: -10)

      expect(result).to be_failure
      expect(result.error.message).to include('Quantity must be greater than 0')
    end

    it 'fails when price is zero' do
      result = described_class.call(**valid_params, price: 0)

      expect(result).to be_failure
      expect(result.error.message).to include('Price must be greater than 0')
    end

    it 'fails when price is negative' do
      result = described_class.call(**valid_params, price: -50)

      expect(result).to be_failure
      expect(result.error.message).to include('Price must be greater than 0')
    end

    it 'fails when executed_at is invalid' do
      result = described_class.call(**valid_params, executed_at: 'invalid-date')

      expect(result).to be_failure
      expect(result.error.message).to include('Executed at invalid date/time format: invalid date')
    end

    it 'fails when algorithm is missing' do
      result = described_class.call(**valid_params.except(:algorithm))

      expect(result).to be_failure
    end
  end
end
