# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FetchQuiverData do
  let(:start_date) { 7.days.ago.to_date }
  let(:end_date) { Date.current }
  let(:sample_trades) do
    [
      {
        ticker: 'AAPL',
        company: 'Apple Inc.',
        trader_name: 'Nancy Pelosi',
        transaction_date: Date.current,
        transaction_type: 'Purchase',
        trade_size_usd: '15001-50000',
        disclosed_at: Time.current
      }
    ]
  end

  let(:client_double) { instance_double(QuiverClient) }

  before do
    allow(QuiverClient).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:fetch_congressional_trades).and_return(sample_trades)
    allow(client_double).to receive(:api_calls).and_return([])
  end

  describe '.call' do
    it 'creates new QuiverTrade records' do
      expect {
        described_class.call(start_date: start_date, end_date: end_date)
      }.to change(QuiverTrade, :count).by(1)
    end

    it 'returns correct counts' do
      result = described_class.call(start_date: start_date, end_date: end_date)
      expect(result.new_trades_count).to eq(1)
      expect(result.trades_count).to eq(1)
    end

    it 'returns record_operations' do
      result = described_class.call(start_date: start_date, end_date: end_date)
      expect(result.record_operations.size).to eq(1)
      expect(result.record_operations.first[:operation]).to eq('created')
      expect(result.record_operations.first[:record]).to be_a(QuiverTrade)
    end

    it 'returns api_calls' do
      allow(client_double).to receive(:api_calls).and_return([{ endpoint: '/test' }])
      result = described_class.call(start_date: start_date, end_date: end_date)
      expect(result.api_calls).to eq([{ endpoint: '/test' }])
    end
  end
end
