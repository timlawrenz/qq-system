# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConsensusDetector, type: :service do
  let(:ticker) { 'AAPL' }
  let(:detector) { described_class.new(ticker: ticker, lookback_days: 45) }

  describe 'constants' do
    it 'defines consensus window' do
      expect(described_class::CONSENSUS_WINDOW_DAYS).to eq(30)
    end

    it 'defines minimum politicians for consensus' do
      expect(described_class::MINIMUM_POLITICIANS_FOR_CONSENSUS).to eq(2)
    end
  end

  describe '#call' do
    context 'with no purchases' do
      it 'returns consensus false' do
        result = detector.call
        expect(result[:is_consensus]).to be false
        expect(result[:politician_count]).to eq(0)
        expect(result[:consensus_strength]).to eq(0.0)
        expect(result[:politicians]).to be_empty
      end
    end

    context 'with single politician purchase' do
      before do
        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Nancy Pelosi',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 10.days.ago.to_date)
      end

      it 'returns consensus false' do
        result = detector.call
        expect(result[:is_consensus]).to be false
        expect(result[:politician_count]).to eq(1)
        expect(result[:consensus_strength]).to eq(0.0)
      end

      it 'includes politician name' do
        result = detector.call
        expect(result[:politicians]).to eq(['Nancy Pelosi'])
      end
    end

    context 'with two politicians purchasing' do
      before do
        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Nancy Pelosi',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 10.days.ago.to_date)

        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Josh Gottheimer',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 15.days.ago.to_date)
      end

      it 'returns consensus true' do
        result = detector.call
        expect(result[:is_consensus]).to be true
        expect(result[:politician_count]).to eq(2)
      end

      it 'calculates base consensus strength' do
        result = detector.call
        # 2 politicians = 2/2.0 = 1.0 base strength
        expect(result[:consensus_strength]).to be >= 1.0
      end

      it 'includes both politician names' do
        result = detector.call
        expect(result[:politicians]).to include('Nancy Pelosi', 'Josh Gottheimer')
      end
    end

    context 'with three politicians purchasing' do
      before do
        %w[Nancy\ Pelosi Josh\ Gottheimer Dan\ Crenshaw].each do |name|
          create(:quiver_trade,
            ticker: 'AAPL',
            trader_name: name,
            trader_source: 'congress',
            transaction_type: 'Purchase',
            transaction_date: 10.days.ago.to_date)
        end
      end

      it 'returns higher consensus strength' do
        result = detector.call
        # 3 politicians = 3/2.0 = 1.5 base strength
        expect(result[:consensus_strength]).to be >= 1.5
        expect(result[:politician_count]).to eq(3)
      end
    end

    context 'with quality score bonus' do
      before do
        # Create high-quality politician profiles
        create(:politician_profile, :high_quality, name: 'Nancy Pelosi')
        create(:politician_profile, :high_quality, name: 'Josh Gottheimer')

        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Nancy Pelosi',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 10.days.ago.to_date)

        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Josh Gottheimer',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 15.days.ago.to_date)
      end

      it 'adds quality bonus to consensus strength' do
        result = detector.call
        # Base: 1.0 + Quality bonus (should be > 0)
        expect(result[:consensus_strength]).to be > 1.0
      end
    end

    context 'with old purchases outside lookback window' do
      before do
        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Nancy Pelosi',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 10.days.ago.to_date)

        # Old purchase - should be excluded
        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Josh Gottheimer',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 60.days.ago.to_date)
      end

      it 'excludes purchases outside lookback window' do
        result = detector.call
        expect(result[:is_consensus]).to be false
        expect(result[:politician_count]).to eq(1)
      end
    end

    context 'with sale transactions' do
      before do
        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Nancy Pelosi',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 10.days.ago.to_date)

        # Sale should be excluded
        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Josh Gottheimer',
          trader_source: 'congress',
          transaction_type: 'Sale',
          transaction_date: 15.days.ago.to_date)
      end

      it 'excludes sale transactions' do
        result = detector.call
        expect(result[:is_consensus]).to be false
        expect(result[:politician_count]).to eq(1)
      end
    end

    context 'with non-congressional trades' do
      before do
        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Nancy Pelosi',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 10.days.ago.to_date)

        # Insider trade should be excluded
        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Tim Cook',
          trader_source: 'insider',
          transaction_type: 'Purchase',
          transaction_date: 15.days.ago.to_date)
      end

      it 'excludes non-congressional trades' do
        result = detector.call
        expect(result[:is_consensus]).to be false
        expect(result[:politician_count]).to eq(1)
      end
    end

    context 'with different tickers' do
      before do
        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Nancy Pelosi',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 10.days.ago.to_date)

        create(:quiver_trade,
          ticker: 'MSFT',
          trader_name: 'Josh Gottheimer',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 15.days.ago.to_date)
      end

      it 'only counts trades for the specified ticker' do
        result = detector.call
        expect(result[:is_consensus]).to be false
        expect(result[:politician_count]).to eq(1)
      end
    end

    context 'with multiple purchases from same politician' do
      before do
        # Nancy buys twice
        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Nancy Pelosi',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 10.days.ago.to_date)

        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Nancy Pelosi',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 20.days.ago.to_date)

        # Josh buys once
        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Josh Gottheimer',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 15.days.ago.to_date)
      end

      it 'counts each politician only once' do
        result = detector.call
        expect(result[:politician_count]).to eq(2)
        expect(result[:politicians]).to contain_exactly('Nancy Pelosi', 'Josh Gottheimer')
      end
    end
  end

  describe '#consensus?' do
    it 'returns false with no purchases' do
      expect(detector.consensus?).to be false
    end

    it 'returns false with single politician' do
      create(:quiver_trade,
        ticker: 'AAPL',
        trader_name: 'Nancy Pelosi',
        trader_source: 'congress',
        transaction_type: 'Purchase',
        transaction_date: 10.days.ago.to_date)

      expect(detector.consensus?).to be false
    end

    it 'returns true with two politicians' do
      create(:quiver_trade,
        ticker: 'AAPL',
        trader_name: 'Nancy Pelosi',
        trader_source: 'congress',
        transaction_type: 'Purchase',
        transaction_date: 10.days.ago.to_date)

      create(:quiver_trade,
        ticker: 'AAPL',
        trader_name: 'Josh Gottheimer',
        trader_source: 'congress',
        transaction_type: 'Purchase',
        transaction_date: 15.days.ago.to_date)

      expect(detector.consensus?).to be true
    end
  end

  describe 'consensus strength calculation' do
    context 'with varying politician counts' do
      it 'calculates strength for 2 politicians' do
        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Politician 1',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 10.days.ago.to_date)

        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Politician 2',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 10.days.ago.to_date)

        result = detector.call
        # 2 politicians: 2/2.0 = 1.0
        expect(result[:consensus_strength]).to eq(1.0)
      end

      it 'caps strength at 3.0 for count multiplier' do
        (1..10).each do |i|
          create(:quiver_trade,
            ticker: 'AAPL',
            trader_name: "Politician #{i}",
            trader_source: 'congress',
            transaction_type: 'Purchase',
            transaction_date: 10.days.ago.to_date)
        end

        result = detector.call
        # Count multiplier capped at 3.0
        expect(result[:consensus_strength]).to be <= 3.7 # 3.0 max + 0.7 max quality
      end
    end

    context 'with quality score bonuses' do
      it 'adds no bonus for quality < 7.0' do
        create(:politician_profile, name: 'Low Quality', quality_score: 6.0)
        create(:politician_profile, name: 'Also Low', quality_score: 6.5)

        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Low Quality',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 10.days.ago.to_date)

        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Also Low',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 15.days.ago.to_date)

        result = detector.call
        # Base: 1.0, Quality bonus: 0.0
        expect(result[:consensus_strength]).to eq(1.0)
      end

      it 'adds 0.3 bonus for quality 7.0-7.9' do
        create(:politician_profile, name: 'Good Quality', quality_score: 7.5)
        create(:politician_profile, name: 'Also Good', quality_score: 7.8)

        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Good Quality',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 10.days.ago.to_date)

        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Also Good',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 15.days.ago.to_date)

        result = detector.call
        # Base: 1.0, Quality bonus: 0.3
        expect(result[:consensus_strength]).to eq(1.3)
      end

      it 'adds 0.7 bonus for quality >= 9.0' do
        create(:politician_profile, name: 'Excellent', quality_score: 9.5)
        create(:politician_profile, name: 'Also Excellent', quality_score: 9.8)

        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Excellent',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 10.days.ago.to_date)

        create(:quiver_trade,
          ticker: 'AAPL',
          trader_name: 'Also Excellent',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 15.days.ago.to_date)

        result = detector.call
        # Base: 1.0, Quality bonus: 0.7
        expect(result[:consensus_strength]).to eq(1.7)
      end
    end
  end

  describe 'custom lookback period' do
    it 'uses custom lookback_days parameter' do
      short_detector = described_class.new(ticker: 'AAPL', lookback_days: 7)

      create(:quiver_trade,
        ticker: 'AAPL',
        trader_name: 'Nancy Pelosi',
        trader_source: 'congress',
        transaction_type: 'Purchase',
        transaction_date: 5.days.ago.to_date)

      # This should be excluded (outside 7-day window)
      create(:quiver_trade,
        ticker: 'AAPL',
        trader_name: 'Josh Gottheimer',
        trader_source: 'congress',
        transaction_type: 'Purchase',
        transaction_date: 10.days.ago.to_date)

      result = short_detector.call
      expect(result[:politician_count]).to eq(1)
    end
  end
end
