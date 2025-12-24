# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FetchInsiderTrades do
  let(:start_date) { Date.parse('2024-01-01') }
  let(:end_date)   { Date.parse('2024-01-31') }
  let(:limit)      { 100 }

  let(:client_double) { instance_double(QuiverClient) }

  let(:base_trade) do
    {
      ticker: 'AAPL',
      company: nil,
      trader_name: 'Tim Cook',
      trader_source: 'insider',
      transaction_date: Date.parse('2024-01-10'),
      transaction_type: 'Purchase',
      trade_size_usd: '150000.0',
      disclosed_at: Time.zone.parse('2024-01-12T15:30:00Z'),
      relationship: 'CEO',
      shares_held: 2000,
      ownership_percent: nil
    }
  end

  before do
    allow(QuiverClient).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:api_calls).and_return([])
  end

  describe '.call' do
    context 'with new insider trades' do
      before do
        allow(client_double).to receive(:fetch_insider_trades).and_return([base_trade])
      end

      it 'creates new QuiverTrade records and returns counts' do
        result = described_class.call(start_date: start_date, end_date: end_date, limit: limit)

        expect(result).to be_success
        expect(result.total_count).to eq(1)
        expect(result.new_count).to eq(1)
        expect(result.updated_count).to eq(0)
        expect(result.error_count).to eq(0)
        expect(QuiverTrade.count).to eq(1)

        trade = QuiverTrade.last
        expect(trade.ticker).to eq('AAPL')
        expect(trade.trader_source).to eq('insider')
        expect(trade.relationship).to eq('CEO')
        expect(trade.shares_held).to eq(2000)
      end
    end

    context 'with existing trades (deduplication)' do
      before do
        # Existing record should be reused
        QuiverTrade.create!(
          ticker: 'AAPL',
          trader_name: 'Tim Cook',
          trader_source: 'insider',
          transaction_type: 'Purchase',
          transaction_date: Date.parse('2024-01-10'),
          trade_size_usd: '150000.0',
          relationship: 'CEO',
          shares_held: 1000
        )

        # API returns duplicate trade plus one more ticker
        allow(client_double).to receive(:fetch_insider_trades).and_return([
                                                                            base_trade,
                                                                            base_trade.merge(ticker: 'MSFT', trader_name: 'Satya Nadella')
                                                                          ])
      end

      it 'does not create duplicates and tracks updated vs new counts' do
        result = described_class.call(start_date: start_date, end_date: end_date, limit: limit)

        expect(result).to be_success
        expect(result.total_count).to eq(2)
        expect(result.new_count).to eq(1)      # MSFT
        expect(result.updated_count).to eq(1)  # AAPL updated shares_held
        expect(result.error_count).to eq(0)

        expect(QuiverTrade.where(ticker: 'AAPL').count).to eq(1)
        expect(QuiverTrade.where(ticker: 'MSFT').count).to eq(1)
      end
    end

    context 'with invalid or filtered trades' do
      let(:invalid_trades) do
        [
          base_trade.merge(transaction_date: nil),                    # missing date
          base_trade.merge(transaction_type: 'Other'),                # filtered transaction type
          base_trade.merge(transaction_date: Date.parse('2023-01-01')) # before start_date
        ]
      end

      before do
        allow(client_double).to receive(:fetch_insider_trades).and_return(invalid_trades)
      end

      it 'skips invalid/filtered trades and creates no records' do
        result = described_class.call(start_date: start_date, end_date: end_date, limit: limit)

        expect(result).to be_success
        expect(result.total_count).to eq(3)
        expect(result.new_count).to eq(0)
        expect(result.updated_count).to eq(0)
        expect(result.error_count).to eq(0)
        expect(QuiverTrade.count).to eq(0)
      end
    end

    context 'when persistence raises errors' do
      before do
        allow(client_double).to receive(:fetch_insider_trades).and_return([base_trade])
        allow(QuiverTrade).to receive(:find_or_initialize_by).and_raise(ActiveRecord::RecordInvalid, 'validation failed')
      end

      it 'counts and records errors without raising' do
        result = described_class.call(start_date: start_date, end_date: end_date, limit: limit)

        expect(result).to be_success
        expect(result.total_count).to eq(1)
        expect(result.new_count).to eq(0)
        expect(result.updated_count).to eq(0)
        expect(result.error_count).to eq(1)
        expect(result.error_messages.first).to match(/AAPL \/ Tim Cook \/ 2024-01-10/)
      end
    end
  end
end
