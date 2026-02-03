# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuiverTrade do
  describe 'validations' do
    let(:valid_attributes) do
      {
        ticker: 'AAPL',
        company: 'Apple Inc.',
        trader_name: 'John Doe',
        trader_source: 'congress',
        transaction_date: Date.current,
        transaction_type: 'Purchase',
        trade_size_usd: '$1,000 - $15,000',
        disclosed_at: Time.current
      }
    end

    it 'is valid with valid attributes' do
      quiver_trade = described_class.new(valid_attributes)
      expect(quiver_trade).to be_valid
    end

    describe 'presence validations' do
      it 'requires ticker' do
        quiver_trade = described_class.new(valid_attributes.except(:ticker))
        expect(quiver_trade).not_to be_valid
        expect(quiver_trade.errors[:ticker]).to include("can't be blank")
      end

      it 'requires transaction_date' do
        quiver_trade = described_class.new(valid_attributes.except(:transaction_date))
        expect(quiver_trade).not_to be_valid
        expect(quiver_trade.errors[:transaction_date]).to include("can't be blank")
      end

      it 'requires transaction_type' do
        quiver_trade = described_class.new(valid_attributes.except(:transaction_type))
        expect(quiver_trade).not_to be_valid
        expect(quiver_trade.errors[:transaction_type]).to include("can't be blank")
      end
    end
  end

  describe 'scopes' do
    let!(:apple_purchase) do
      create(:quiver_trade, ticker: 'AAPL', transaction_type: 'Purchase', transaction_date: 1.day.ago)
    end
    let!(:apple_sale) { create(:quiver_trade, ticker: 'AAPL', transaction_type: 'Sale', transaction_date: 2.days.ago) }
    let!(:google_purchase) do
      create(:quiver_trade, ticker: 'GOOGL', transaction_type: 'Purchase', transaction_date: 50.days.ago)
    end

    describe '.for_ticker' do
      it 'returns trades for a specific ticker' do
        expect(described_class.for_ticker('AAPL')).to contain_exactly(apple_purchase, apple_sale)
      end
    end

    describe '.purchases' do
      it 'returns only purchase trades' do
        expect(described_class.purchases).to contain_exactly(apple_purchase, google_purchase)
      end
    end

    describe '.sales' do
      it 'returns only sale trades' do
        expect(described_class.sales).to contain_exactly(apple_sale)
      end
    end

    describe '.recent' do
      it 'returns trades from the last 45 days by default' do
        expect(described_class.recent).to contain_exactly(apple_purchase, apple_sale)
      end

      it 'accepts custom number of days' do
        expect(described_class.recent(60)).to contain_exactly(apple_purchase, apple_sale, google_purchase)
      end
    end

    describe '.between_dates' do
      it 'returns trades between specified dates' do
        expect(described_class.between_dates(3.days.ago, Date.current)).to contain_exactly(apple_purchase, apple_sale)
      end
    end

    describe '.ordered_by_date' do
      it 'returns trades ordered by transaction date' do
        expect(described_class.ordered_by_date).to eq([google_purchase, apple_sale, apple_purchase])
      end
    end
  end

  describe 'database columns' do
    it 'has the expected columns' do
      expected_columns = %w[
        id ticker company trader_name trader_source transaction_date
        transaction_type trade_size_usd disclosed_at relationship shares_held
        ownership_percent trade_type created_at updated_at
      ]
      expect(described_class.column_names).to include(*expected_columns)
    end
  end

  describe 'insider scopes' do
    let!(:insider_ceo) do
      create(:quiver_trade,
             trader_source: 'insider',
             relationship: 'CEO',
             trade_type: 'Form4')
    end

    let!(:insider_director) do
      create(:quiver_trade,
             trader_source: 'insider',
             relationship: 'Director',
             trade_type: 'Form4')
    end

    let!(:congress_trade) do
      create(:quiver_trade,
             trader_source: 'congress',
             relationship: nil,
             trade_type: nil)
    end

    it 'scopes insiders correctly' do
      expect(described_class.insiders).to include(insider_ceo, insider_director)
      expect(described_class.insiders).not_to include(congress_trade)
    end

    it 'scopes c_suite correctly' do
      expect(described_class.c_suite).to include(insider_ceo)
      expect(described_class.c_suite).not_to include(insider_director)
    end

    it 'scopes form4_trades correctly' do
      expect(described_class.form4_trades).to include(insider_ceo, insider_director)
      expect(described_class.form4_trades).not_to include(congress_trade)
    end
  end

  describe 'factory' do
    it 'creates a valid quiver trade' do
      quiver_trade = create(:quiver_trade)
      expect(quiver_trade).to be_persisted
      expect(quiver_trade.ticker).to be_present
      expect(quiver_trade.transaction_date).to be_present
      expect(quiver_trade.transaction_type).to be_present
    end
  end
end
