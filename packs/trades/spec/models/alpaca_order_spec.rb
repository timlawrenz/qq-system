# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlpacaOrder do
  describe 'associations' do
    it 'belongs to quiver_trade optionally' do
      association = described_class.reflect_on_association(:quiver_trade)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be true
    end
  end

  describe 'validations' do
    let(:valid_attributes) do
      {
        alpaca_order_id: SecureRandom.uuid,
        symbol: 'AAPL',
        side: 'buy',
        status: 'filled'
      }
    end

    it 'is valid with valid attributes' do
      alpaca_order = described_class.new(valid_attributes)
      expect(alpaca_order).to be_valid
    end

    describe 'presence validations' do
      it 'requires alpaca_order_id' do
        alpaca_order = described_class.new(valid_attributes.except(:alpaca_order_id))
        expect(alpaca_order).not_to be_valid
        expect(alpaca_order.errors[:alpaca_order_id]).to include("can't be blank")
      end

      it 'requires symbol' do
        alpaca_order = described_class.new(valid_attributes.except(:symbol))
        expect(alpaca_order).not_to be_valid
        expect(alpaca_order.errors[:symbol]).to include("can't be blank")
      end

      it 'requires side' do
        alpaca_order = described_class.new(valid_attributes.except(:side))
        expect(alpaca_order).not_to be_valid
        expect(alpaca_order.errors[:side]).to include("can't be blank")
      end

      it 'requires status' do
        alpaca_order = described_class.new(valid_attributes.except(:status))
        expect(alpaca_order).not_to be_valid
        expect(alpaca_order.errors[:status]).to include("can't be blank")
      end
    end

    describe 'uniqueness validations' do
      it 'requires alpaca_order_id to be unique' do
        order_id = SecureRandom.uuid
        create(:alpaca_order, alpaca_order_id: order_id)
        duplicate_order = build(:alpaca_order, alpaca_order_id: order_id)

        expect(duplicate_order).not_to be_valid
        expect(duplicate_order.errors[:alpaca_order_id]).to include('has already been taken')
      end
    end

    describe 'side validation' do
      it 'accepts buy as valid side' do
        alpaca_order = described_class.new(valid_attributes.merge(side: 'buy'))
        expect(alpaca_order).to be_valid
      end

      it 'accepts sell as valid side' do
        alpaca_order = described_class.new(valid_attributes.merge(side: 'sell'))
        expect(alpaca_order).to be_valid
      end

      it 'rejects invalid side values' do
        alpaca_order = described_class.new(valid_attributes.merge(side: 'invalid'))
        expect(alpaca_order).not_to be_valid
        expect(alpaca_order.errors[:side]).to include('is not included in the list')
      end
    end
  end

  describe 'scopes' do
    before do
      create(:alpaca_order, symbol: 'AAPL', side: 'buy', status: 'filled', filled_at: 1.hour.ago)
      create(:alpaca_order, symbol: 'AAPL', side: 'sell', status: 'pending', filled_at: nil)
      create(:alpaca_order, symbol: 'TSLA', side: 'buy', status: 'cancelled', filled_at: nil)
    end

    describe '.for_symbol' do
      it 'returns orders for a specific symbol' do
        expect(described_class.for_symbol('AAPL').count).to eq(2)
        expect(described_class.for_symbol('TSLA').count).to eq(1)
      end
    end

    describe '.buys' do
      it 'returns only buy orders' do
        expect(described_class.buys.count).to eq(2)
        expect(described_class.buys.pluck(:side)).to all(eq('buy'))
      end
    end

    describe '.sells' do
      it 'returns only sell orders' do
        expect(described_class.sells.count).to eq(1)
        expect(described_class.sells.pluck(:side)).to all(eq('sell'))
      end
    end

    describe '.by_status' do
      it 'returns orders with specific status' do
        expect(described_class.by_status('filled').count).to eq(1)
        expect(described_class.by_status('pending').count).to eq(1)
        expect(described_class.by_status('cancelled').count).to eq(1)
      end
    end

    describe '.filled' do
      it 'returns orders that have been filled' do
        expect(described_class.filled.count).to eq(1)
        expect(described_class.filled.pluck(:filled_at)).to all(be_present)
      end
    end

    describe '.pending' do
      it 'returns orders that have not been filled' do
        expect(described_class.pending.count).to eq(2)
        expect(described_class.pending.pluck(:filled_at)).to all(be_nil)
      end
    end
  end

  describe 'database columns' do
    it 'has the expected columns' do
      expected_columns = %w[
        alpaca_order_id quiver_trade_id symbol side status qty notional
        order_type time_in_force submitted_at filled_at filled_avg_price
        created_at updated_at
      ]
      expect(described_class.column_names).to include(*expected_columns)
    end
  end

  describe 'factory' do
    it 'creates a valid alpaca_order' do
      alpaca_order = create(:alpaca_order)
      expect(alpaca_order).to be_persisted
      expect(alpaca_order.alpaca_order_id).to be_present
      expect(alpaca_order.symbol).to be_present
      expect(alpaca_order.side).to be_present
      expect(alpaca_order.status).to be_present
    end

    it 'creates valid alpaca_order with quiver_trade' do
      alpaca_order = create(:alpaca_order, :with_quiver_trade)
      expect(alpaca_order).to be_persisted
      expect(alpaca_order.quiver_trade).to be_present
    end

    it 'creates valid pending order' do
      alpaca_order = create(:alpaca_order, :pending)
      expect(alpaca_order).to be_persisted
      expect(alpaca_order.status).to eq('pending')
      expect(alpaca_order.filled_at).to be_nil
    end
  end

  describe 'database constraints and relationships' do
    it 'allows alpaca_order without quiver_trade' do
      alpaca_order = create(:alpaca_order, quiver_trade: nil)
      expect(alpaca_order).to be_persisted
      expect(alpaca_order.quiver_trade).to be_nil
    end

    it 'allows alpaca_order with valid quiver_trade' do
      quiver_trade = create(:quiver_trade)
      alpaca_order = create(:alpaca_order, quiver_trade: quiver_trade)
      expect(alpaca_order).to be_persisted
      expect(alpaca_order.quiver_trade).to eq(quiver_trade)
    end
  end
end
