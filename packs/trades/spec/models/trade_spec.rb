# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trade do
  describe 'associations' do
    it 'belongs to algorithm' do
      expect(described_class.reflect_on_association(:algorithm).macro).to eq(:belongs_to)
    end
  end

  describe 'validations' do
    let(:valid_attributes) do
      {
        algorithm: create(:algorithm),
        symbol: 'AAPL',
        executed_at: Time.current,
        side: 'buy',
        quantity: 100.0,
        price: 150.50
      }
    end

    it 'is valid with valid attributes' do
      trade = described_class.new(valid_attributes)
      expect(trade).to be_valid
    end

    describe 'presence validations' do
      it 'requires symbol' do
        trade = described_class.new(valid_attributes.except(:symbol))
        expect(trade).not_to be_valid
        expect(trade.errors[:symbol]).to include("can't be blank")
      end

      it 'requires executed_at' do
        trade = described_class.new(valid_attributes.except(:executed_at))
        expect(trade).not_to be_valid
        expect(trade.errors[:executed_at]).to include("can't be blank")
      end

      it 'requires side' do
        trade = described_class.new(valid_attributes.except(:side))
        expect(trade).not_to be_valid
        expect(trade.errors[:side]).to include("can't be blank")
      end

      it 'requires quantity' do
        trade = described_class.new(valid_attributes.except(:quantity))
        expect(trade).not_to be_valid
        expect(trade.errors[:quantity]).to include("can't be blank")
      end

      it 'requires price' do
        trade = described_class.new(valid_attributes.except(:price))
        expect(trade).not_to be_valid
        expect(trade.errors[:price]).to include("can't be blank")
      end

      it 'requires algorithm' do
        trade = described_class.new(valid_attributes.except(:algorithm))
        expect(trade).not_to be_valid
        expect(trade.errors[:algorithm]).to include('must exist')
      end
    end

    describe 'side validation' do
      it 'accepts buy as valid side' do
        trade = described_class.new(valid_attributes.merge(side: 'buy'))
        expect(trade).to be_valid
      end

      it 'accepts sell as valid side' do
        trade = described_class.new(valid_attributes.merge(side: 'sell'))
        expect(trade).to be_valid
      end

      it 'rejects invalid side values' do
        trade = described_class.new(valid_attributes.merge(side: 'invalid'))
        expect(trade).not_to be_valid
        expect(trade.errors[:side]).to include('is not included in the list')
      end
    end

    describe 'numericality validations' do
      it 'requires quantity to be greater than 0' do
        trade = described_class.new(valid_attributes.merge(quantity: 0))
        expect(trade).not_to be_valid
        expect(trade.errors[:quantity]).to include('must be greater than 0')
      end

      it 'requires quantity to be positive' do
        trade = described_class.new(valid_attributes.merge(quantity: -10))
        expect(trade).not_to be_valid
        expect(trade.errors[:quantity]).to include('must be greater than 0')
      end

      it 'requires price to be greater than 0' do
        trade = described_class.new(valid_attributes.merge(price: 0))
        expect(trade).not_to be_valid
        expect(trade.errors[:price]).to include('must be greater than 0')
      end

      it 'requires price to be positive' do
        trade = described_class.new(valid_attributes.merge(price: -50))
        expect(trade).not_to be_valid
        expect(trade.errors[:price]).to include('must be greater than 0')
      end
    end
  end

  describe 'database columns' do
    it 'has the expected columns' do
      expected_columns = %w[
        algorithm_id symbol executed_at side quantity price
        created_at updated_at
      ]
      expect(described_class.column_names).to include(*expected_columns)
    end
  end

  describe 'factory' do
    it 'creates a valid trade' do
      trade = create(:trade)
      expect(trade).to be_persisted
      expect(trade.symbol).to be_present
      expect(trade.executed_at).to be_present
      expect(trade.side).to be_present
      expect(trade.quantity).to be_positive
      expect(trade.price).to be_positive
      expect(trade.algorithm).to be_present
    end
  end

  describe 'database constraints' do
    it 'validates foreign key relationship' do
      trade_attributes = attributes_for(:trade).merge(algorithm_id: 99_999)
      trade = described_class.new(trade_attributes)

      expect(trade).not_to be_valid
      expect(trade.errors[:algorithm]).to include('must exist')
    end
  end
end
