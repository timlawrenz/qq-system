# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HistoricalBar do
  describe 'validations' do
    let(:valid_attributes) do
      {
        symbol: 'AAPL',
        timestamp: Time.current,
        open: 150.00,
        high: 155.00,
        low: 149.00,
        close: 152.00,
        volume: 1000
      }
    end

    it 'is valid with valid attributes' do
      historical_bar = described_class.new(valid_attributes)
      expect(historical_bar).to be_valid
    end

    describe 'presence validations' do
      it 'requires symbol' do
        historical_bar = described_class.new(valid_attributes.except(:symbol))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:symbol]).to include("can't be blank")
      end

      it 'requires timestamp' do
        historical_bar = described_class.new(valid_attributes.except(:timestamp))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:timestamp]).to include("can't be blank")
      end

      it 'requires open' do
        historical_bar = described_class.new(valid_attributes.except(:open))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:open]).to include("can't be blank")
      end

      it 'requires high' do
        historical_bar = described_class.new(valid_attributes.except(:high))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:high]).to include("can't be blank")
      end

      it 'requires low' do
        historical_bar = described_class.new(valid_attributes.except(:low))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:low]).to include("can't be blank")
      end

      it 'requires close' do
        historical_bar = described_class.new(valid_attributes.except(:close))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:close]).to include("can't be blank")
      end

      it 'requires volume' do
        historical_bar = described_class.new(valid_attributes.except(:volume))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:volume]).to include("can't be blank")
      end
    end

    describe 'numericality validations' do
      it 'requires open to be greater than 0' do
        historical_bar = described_class.new(valid_attributes.merge(open: 0))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:open]).to include('must be greater than 0')
      end

      it 'requires high to be greater than 0' do
        historical_bar = described_class.new(valid_attributes.merge(high: -1))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:high]).to include('must be greater than 0')
      end

      it 'requires low to be greater than 0' do
        historical_bar = described_class.new(valid_attributes.merge(low: 0))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:low]).to include('must be greater than 0')
      end

      it 'requires close to be greater than 0' do
        historical_bar = described_class.new(valid_attributes.merge(close: -5))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:close]).to include('must be greater than 0')
      end

      it 'allows volume to be 0' do
        historical_bar = described_class.new(valid_attributes.merge(volume: 0))
        expect(historical_bar).to be_valid
      end

      it 'requires volume to be greater than or equal to 0' do
        historical_bar = described_class.new(valid_attributes.merge(volume: -1))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:volume]).to include('must be greater than or equal to 0')
      end
    end

    describe 'price range validations' do
      it 'requires high to be greater than or equal to low' do
        historical_bar = described_class.new(valid_attributes.merge(high: 100, low: 105))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:high]).to include('must be greater than or equal to low')
      end

      it 'allows high to equal low' do
        historical_bar = described_class.new(valid_attributes.merge(high: 100, low: 100, open: 100, close: 100))
        expect(historical_bar).to be_valid
      end

      it 'requires open to be within high-low range' do
        historical_bar = described_class.new(valid_attributes.merge(open: 160, high: 155, low: 149))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:open]).to include('must be between low and high')
      end

      it 'requires close to be within high-low range' do
        historical_bar = described_class.new(valid_attributes.merge(close: 140, high: 155, low: 149))
        expect(historical_bar).not_to be_valid
        expect(historical_bar.errors[:close]).to include('must be between low and high')
      end
    end
  end

  describe 'database constraints' do
    let(:valid_attributes) do
      {
        symbol: 'AAPL',
        timestamp: Time.current,
        open: 150.00,
        high: 155.00,
        low: 149.00,
        close: 152.00,
        volume: 1000
      }
    end

    it 'enforces uniqueness of symbol and timestamp' do
      described_class.create!(valid_attributes)

      duplicate_bar = described_class.new(valid_attributes)
      expect { duplicate_bar.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'scopes' do
    let!(:aapl_bar_today) do
      described_class.create!(
        symbol: 'AAPL',
        timestamp: 1.day.ago,
        open: 150.00,
        high: 155.00,
        low: 149.00,
        close: 152.00,
        volume: 1000
      )
    end

    let!(:aapl_bar_yesterday) do
      described_class.create!(
        symbol: 'AAPL',
        timestamp: 2.days.ago,
        open: 148.00,
        high: 153.00,
        low: 147.00,
        close: 150.00,
        volume: 1500
      )
    end

    let!(:msft_bar) do
      described_class.create!(
        symbol: 'MSFT',
        timestamp: 1.day.ago,
        open: 300.00,
        high: 305.00,
        low: 299.00,
        close: 302.00,
        volume: 800
      )
    end

    describe '.for_symbol' do
      it 'returns bars for the specified symbol' do
        aapl_bars = described_class.for_symbol('AAPL')
        expect(aapl_bars).to contain_exactly(aapl_bar_today, aapl_bar_yesterday)
      end
    end

    describe '.between_dates' do
      it 'returns bars between specified dates' do
        bars = described_class.between_dates(1.5.days.ago, 0.5.days.ago)
        expect(bars).to contain_exactly(aapl_bar_today, msft_bar)
      end
    end

    describe '.ordered_by_timestamp' do
      it 'returns bars ordered by timestamp' do
        bars = described_class.ordered_by_timestamp
        expect(bars).to eq([aapl_bar_yesterday, aapl_bar_today, msft_bar])
      end
    end
  end
end
