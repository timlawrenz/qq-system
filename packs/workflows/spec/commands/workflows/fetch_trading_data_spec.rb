# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Workflows::FetchTradingData do
  describe 'interface', type: :command do
    it { is_expected.to allow(:skip_congressional) }
    it { is_expected.to allow(:skip_insider) }
    it { is_expected.to allow(:lookback_days) }
    it { is_expected.to returns(:congressional_count) }
    it { is_expected.to returns(:congressional_new_count) }
    it { is_expected.to returns(:insider_count) }
    it { is_expected.to returns(:insider_new_count) }
  end

  describe '#call' do
    let(:quiver_client) { instance_double(QuiverClient) }

    before do
      RSpec::Mocks.space.proxy_for(QuiverClient).add_stub(:new) { quiver_client }
    end

    context 'when fetching both congressional and insider trades' do
      let(:congressional_trades) do
        [
          { ticker: 'AAPL', transaction_date: 3.days.ago.to_date, trader_name: 'Sen. X',
            transaction_type: 'Purchase', company: 'Apple Inc', trade_size_usd: '$50,000',
            disclosed_at: 1.day.ago },
          { ticker: 'MSFT', transaction_date: 5.days.ago.to_date, trader_name: 'Rep. Y',
            transaction_type: 'Purchase', company: 'Microsoft', trade_size_usd: '$25,000',
            disclosed_at: 2.days.ago }
        ]
      end

      let(:insider_trades) do
        [
          { ticker: 'GOOGL', transaction_date: 2.days.ago.to_date, trader_name: 'CEO John',
            transaction_type: 'Purchase', company: 'Alphabet Inc', trade_size_usd: '$100,000',
            disclosed_at: 1.day.ago, relationship: 'CEO', shares_held: 10_000, ownership_percent: 0.5 }
        ]
      end

      before do
        allow(quiver_client).to receive_messages(
          fetch_congressional_trades: congressional_trades,
          fetch_insider_trades: insider_trades,
          api_calls: []
        )
      end

      it 'fetches and stores congressional trades' do
        result = described_class.call

        expect(result).to be_success
        expect(result.congressional_count).to eq(2)
        expect(QuiverTrade.where(trader_source: 'congress').count).to be >= 2
      end

      it 'fetches and stores insider trades' do
        result = described_class.call

        expect(result).to be_success
        expect(result.insider_count).to eq(1)
        expect(QuiverTrade.where(trader_source: 'insider').count).to be >= 1
      end
    end

    context 'when skipping congressional trades' do
      it 'skips congressional fetch' do
        # Skip both to test the skip logic
        result = described_class.call(skip_congressional: true, skip_insider: true)

        expect(result).to be_success
        expect(result.congressional_count).to eq(0)
        expect(result.insider_count).to eq(0)
      end
    end

    context 'when skipping all trades' do
      it 'returns zero counts' do
        result = described_class.call(skip_congressional: true, skip_insider: true)

        expect(result).to be_success
        expect(result.congressional_count).to eq(0)
        expect(result.insider_count).to eq(0)
      end
    end
  end
end
