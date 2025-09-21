# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TargetPosition do
  describe 'initialization' do
    let(:valid_attributes) do
      {
        symbol: 'AAPL',
        asset_type: :stock,
        target_value: BigDecimal('1000.50'),
        details: { strike_price: 150.0 }
      }
    end

    it 'initializes with all required attributes' do
      target_position = described_class.new(**valid_attributes)

      expect(target_position.symbol).to eq('AAPL')
      expect(target_position.asset_type).to eq(:stock)
      expect(target_position.target_value).to eq(BigDecimal('1000.50'))
      expect(target_position.details).to eq({ strike_price: 150.0 })
    end

    it 'initializes with empty details hash by default' do
      target_position = described_class.new(
        symbol: 'AAPL',
        asset_type: :stock,
        target_value: BigDecimal('1000.50')
      )

      expect(target_position.details).to eq({})
    end

    it 'accepts symbol as a string' do
      target_position = described_class.new(
        symbol: 'GOOGL',
        asset_type: :stock,
        target_value: BigDecimal('2500.75')
      )

      expect(target_position.symbol).to eq('GOOGL')
    end

    it 'accepts asset_type as a symbol' do
      target_position = described_class.new(
        symbol: 'AAPL',
        asset_type: :option,
        target_value: BigDecimal('500.00')
      )

      expect(target_position.asset_type).to eq(:option)
    end

    it 'accepts target_value as a Decimal' do
      target_value = BigDecimal('1234.56')
      target_position = described_class.new(
        symbol: 'AAPL',
        asset_type: :stock,
        target_value: target_value
      )

      expect(target_position.target_value).to eq(target_value)
    end
  end

  describe 'equality' do
    let(:attributes) do
      {
        symbol: 'AAPL',
        asset_type: :stock,
        target_value: BigDecimal('1000.50'),
        details: { strike_price: 150.0 }
      }
    end

    it 'returns true for objects with identical attributes' do
      position1 = described_class.new(**attributes)
      position2 = described_class.new(**attributes)

      expect(position1).to eq(position2)
    end

    it 'returns false for objects with different symbols' do
      position1 = described_class.new(**attributes)
      position2 = described_class.new(**attributes, symbol: 'GOOGL')

      expect(position1).not_to eq(position2)
    end

    it 'returns false for objects with different asset_types' do
      position1 = described_class.new(**attributes)
      position2 = described_class.new(**attributes, asset_type: :option)

      expect(position1).not_to eq(position2)
    end

    it 'returns false for objects with different target_values' do
      position1 = described_class.new(**attributes)
      position2 = described_class.new(**attributes, target_value: BigDecimal('2000.00'))

      expect(position1).not_to eq(position2)
    end

    it 'returns false for objects with different details' do
      position1 = described_class.new(**attributes)
      position2 = described_class.new(**attributes, details: { option_type: 'call' })

      expect(position1).not_to eq(position2)
    end

    it 'returns false when compared to non-TargetPosition objects' do
      position = described_class.new(**attributes)

      expect(position).not_to eq('not a target position')
      expect(position).not_to be_nil
      expect(position).not_to eq({})
    end
  end

  describe '#to_h' do
    it 'returns a hash representation of the object' do
      attributes = {
        symbol: 'AAPL',
        asset_type: :stock,
        target_value: BigDecimal('1000.50'),
        details: { strike_price: 150.0 }
      }
      target_position = described_class.new(**attributes)

      expect(target_position.to_h).to eq(attributes)
    end

    it 'returns a hash with empty details when details is empty' do
      target_position = described_class.new(
        symbol: 'AAPL',
        asset_type: :stock,
        target_value: BigDecimal('1000.50')
      )

      expected_hash = {
        symbol: 'AAPL',
        asset_type: :stock,
        target_value: BigDecimal('1000.50'),
        details: {}
      }

      expect(target_position.to_h).to eq(expected_hash)
    end
  end

  describe 'immutability' do
    it 'provides read-only access to attributes' do
      target_position = described_class.new(
        symbol: 'AAPL',
        asset_type: :stock,
        target_value: BigDecimal('1000.50'),
        details: { strike_price: 150.0 }
      )

      expect(target_position).to respond_to(:symbol)
      expect(target_position).to respond_to(:asset_type)
      expect(target_position).to respond_to(:target_value)
      expect(target_position).to respond_to(:details)

      expect(target_position).not_to respond_to(:symbol=)
      expect(target_position).not_to respond_to(:asset_type=)
      expect(target_position).not_to respond_to(:target_value=)
      expect(target_position).not_to respond_to(:details=)
    end
  end
end
