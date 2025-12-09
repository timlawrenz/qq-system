# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PoliticianScorer, type: :service do
  let(:politician) { create(:politician_profile, name: 'Test Politician') }
  let(:scorer) { described_class.new(politician) }

  describe '#call' do
    context 'with insufficient trade history' do
      before do
        create_list(:quiver_trade, 3,
                    trader_name: politician.name,
                    trader_source: 'congress',
                    transaction_type: 'Purchase',
                    transaction_date: 30.days.ago.to_date)
      end

      it 'returns default score of 5.0' do
        expect(scorer.call).to eq(5.0)
      end

      it 'updates politician with default score' do
        scorer.call
        politician.reload

        expect(politician.quality_score).to eq(5.0)
        expect(politician.total_trades).to eq(3)
        expect(politician.winning_trades).to be_nil
        expect(politician.average_return).to be_nil
        expect(politician.last_scored_at).to be_present
      end
    end

    context 'with sufficient trade history' do
      before do
        # Create 10 purchases
        create_list(:quiver_trade, 10,
                    trader_name: politician.name,
                    trader_source: 'congress',
                    transaction_type: 'Purchase',
                    transaction_date: 60.days.ago.to_date)
      end

      it 'calculates and returns a quality score' do
        score = scorer.call
        expect(score).to be_a(Numeric)
        expect(score).to be_between(0, 10)
      end

      it 'updates politician profile with scoring data' do
        scorer.call
        politician.reload

        expect(politician.quality_score).to be_present
        expect(politician.total_trades).to eq(10)
        expect(politician.winning_trades).to be >= 0
        expect(politician.average_return).to be_present
        expect(politician.last_scored_at).to be_within(1.second).of(Time.current)
      end
    end

    context 'with mixed purchase and sale history' do
      let!(:aapl_purchases) do
        create_list(:quiver_trade, 3,
                    trader_name: politician.name,
                    trader_source: 'congress',
                    transaction_type: 'Purchase',
                    ticker: 'AAPL',
                    transaction_date: 90.days.ago.to_date)
      end

      let!(:aapl_sales) do
        create_list(:quiver_trade, 1,
                    trader_name: politician.name,
                    trader_source: 'congress',
                    transaction_type: 'Sale',
                    ticker: 'AAPL',
                    transaction_date: 30.days.ago.to_date)
      end

      let!(:msft_purchases) do
        create_list(:quiver_trade, 2,
                    trader_name: politician.name,
                    trader_source: 'congress',
                    transaction_type: 'Purchase',
                    ticker: 'MSFT',
                    transaction_date: 60.days.ago.to_date)
      end

      it 'calculates score based on purchase patterns' do
        score = scorer.call
        expect(score).to be_between(0, 10)
      end

      it 'correctly counts winning trades using heuristics' do
        scorer.call
        politician.reload

        # MSFT: no sales = likely winning (2 trades)
        # AAPL: 3 purchases, 1 sale, remaining treated at 60% win rate
        expect(politician.winning_trades).to be > 0
      end
    end

    context 'with only recent trades' do
      before do
        create_list(:quiver_trade, 6,
                    trader_name: politician.name,
                    trader_source: 'congress',
                    transaction_type: 'Purchase',
                    transaction_date: 10.days.ago.to_date)

        # Old trades should be excluded
        create_list(:quiver_trade, 5,
                    trader_name: politician.name,
                    trader_source: 'congress',
                    transaction_type: 'Purchase',
                    transaction_date: 400.days.ago.to_date)
      end

      it 'only considers trades within lookback period' do
        scorer.call
        politician.reload

        expect(politician.total_trades).to eq(6)
      end
    end

    context 'with high win rate pattern' do
      before do
        # 10 purchases across different tickers, no sales = high win rate
        %w[AAPL MSFT GOOGL AMZN NVDA TSLA META NFLX].each do |ticker|
          create(:quiver_trade,
                 trader_name: politician.name,
                 trader_source: 'congress',
                 transaction_type: 'Purchase',
                 ticker: ticker,
                 transaction_date: 60.days.ago.to_date)
        end
      end

      it 'produces a higher quality score' do
        score = scorer.call
        expect(score).to be > 6.0
      end
    end

    context 'score calculation formula' do
      before do
        # Create exactly 10 purchases to make calculation predictable
        create_list(:quiver_trade, 10,
                    trader_name: politician.name,
                    trader_source: 'congress',
                    transaction_type: 'Purchase',
                    ticker: 'TEST',
                    transaction_date: 60.days.ago.to_date)
      end

      it 'uses formula: (win_rate * 0.6) + (avg_return * 0.4)' do
        score = scorer.call
        politician.reload

        # Verify score is within expected range based on formula
        # With no sales, win rate should be 100%
        # win_rate_component = 1.0 * 6.0 = 6.0
        # return_component is calculated from win rate proxy

        expect(score).to be >= 6.0
        expect(score).to be <= 10.0
      end
    end
  end

  describe 'minimum trades requirement' do
    it 'requires at least 5 trades for scoring' do
      expect(described_class::MINIMUM_TRADES_FOR_SCORING).to eq(5)
    end
  end

  describe 'lookback period' do
    it 'looks back 365 days' do
      expect(described_class::LOOKBACK_PERIOD_DAYS).to eq(365)
    end
  end

  describe 'edge cases' do
    context 'when politician has no trades' do
      it 'returns default score' do
        expect(scorer.call).to eq(5.0)
      end
    end

    context 'when politician has only sale transactions' do
      before do
        create_list(:quiver_trade, 6,
                    trader_name: politician.name,
                    trader_source: 'congress',
                    transaction_type: 'Sale',
                    transaction_date: 60.days.ago.to_date)
      end

      it 'returns default score (only purchases are scored)' do
        expect(scorer.call).to eq(5.0)
      end
    end

    context 'when score calculation is called multiple times' do
      before do
        create_list(:quiver_trade, 10,
                    trader_name: politician.name,
                    trader_source: 'congress',
                    transaction_type: 'Purchase',
                    transaction_date: 60.days.ago.to_date)
      end

      it 'updates the score each time' do
        first_score = scorer.call
        first_scored_at = politician.reload.last_scored_at

        sleep 0.1

        second_scorer = described_class.new(politician)
        second_score = second_scorer.call
        second_scored_at = politician.reload.last_scored_at

        expect(second_scored_at).to be > first_scored_at
        expect(second_score).to eq(first_score)
      end
    end
  end
end
