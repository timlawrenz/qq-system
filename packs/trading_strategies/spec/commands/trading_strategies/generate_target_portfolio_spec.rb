# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingStrategies::GenerateTargetPortfolio do
  let(:mock_alpaca_service) { instance_double(AlpacaService) }

  before do
    allow(AlpacaService).to receive(:new).and_return(mock_alpaca_service)
  end

  describe 'successful portfolio generation' do
    context 'with purchase trades and positive equity' do
      before do
        create(:quiver_trade, ticker: 'AAPL', transaction_type: 'Purchase', transaction_date: 30.days.ago)
        create(:quiver_trade, ticker: 'GOOGL', transaction_type: 'Purchase', transaction_date: 20.days.ago)
        create(:quiver_trade, ticker: 'MSFT', transaction_type: 'Purchase', transaction_date: 10.days.ago)
        allow(mock_alpaca_service).to receive(:account_equity).and_return(BigDecimal('100000.00'))
      end

      it 'generates target positions for unique tickers with equal weights' do
        result = described_class.call

        expect(result).to be_success
        expect(result.target_positions).to be_an(Array)
        expect(result.target_positions.size).to eq(3)

        # Check that each position has equal allocation
        allocation_per_ticker = BigDecimal('100000.00') / 3
        result.target_positions.each do |position|
          expect(position).to be_a(TargetPosition)
          expect(position.asset_type).to eq(:stock)
          expect(position.target_value).to eq(allocation_per_ticker)
        end

        # Check that all tickers are included
        symbols = result.target_positions.map(&:symbol)
        expect(symbols).to match_array(%w[AAPL GOOGL MSFT])
      end
    end

    context 'with duplicate ticker purchases' do
      before do
        create(:quiver_trade, ticker: 'AAPL', transaction_type: 'Purchase', transaction_date: 30.days.ago)
        create(:quiver_trade, ticker: 'AAPL', transaction_type: 'Purchase', transaction_date: 20.days.ago)
        create(:quiver_trade, ticker: 'GOOGL', transaction_type: 'Purchase', transaction_date: 10.days.ago)
        allow(mock_alpaca_service).to receive(:account_equity).and_return(BigDecimal('50000.00'))
      end

      it 'includes each unique ticker only once' do
        result = described_class.call

        expect(result).to be_success
        expect(result.target_positions.size).to eq(2)

        symbols = result.target_positions.map(&:symbol)
        expect(symbols).to match_array(%w[AAPL GOOGL])

        # Each position should get 50% allocation
        result.target_positions.each do |position|
          expect(position.target_value).to eq(BigDecimal('25000.00'))
        end
      end
    end

    context 'with mixed transaction types' do
      before do
        create(:quiver_trade, ticker: 'AAPL', transaction_type: 'Purchase', transaction_date: 30.days.ago)
        create(:quiver_trade, ticker: 'GOOGL', transaction_type: 'Sale', transaction_date: 20.days.ago)
        create(:quiver_trade, ticker: 'MSFT', transaction_type: 'Purchase', transaction_date: 10.days.ago)
        allow(mock_alpaca_service).to receive(:account_equity).and_return(BigDecimal('60000.00'))
      end

      it 'only includes tickers from Purchase transactions' do
        result = described_class.call

        expect(result).to be_success
        expect(result.target_positions.size).to eq(2)

        symbols = result.target_positions.map(&:symbol)
        expect(symbols).to match_array(%w[AAPL MSFT])
        expect(symbols).not_to include('GOOGL')

        # Each position should get 50% allocation
        result.target_positions.each do |position|
          expect(position.target_value).to eq(BigDecimal('30000.00'))
        end
      end
    end
  end

  describe 'edge cases' do
    context 'with no purchase trades' do
      before do
        create(:quiver_trade, ticker: 'GOOGL', transaction_type: 'Sale', transaction_date: 20.days.ago)
        allow(mock_alpaca_service).to receive(:account_equity).and_return(BigDecimal('100000.00'))
      end

      it 'returns empty target positions array' do
        result = described_class.call

        expect(result).to be_success
        expect(result.target_positions).to eq([])
      end
    end

    context 'with purchases older than 45 days' do
      before do
        create(:quiver_trade, ticker: 'AAPL', transaction_type: 'Purchase', transaction_date: 50.days.ago)
        create(:quiver_trade, ticker: 'GOOGL', transaction_type: 'Purchase', transaction_date: 20.days.ago)
        allow(mock_alpaca_service).to receive(:account_equity).and_return(BigDecimal('100000.00'))
      end

      it 'only includes purchases from the last 45 days' do
        result = described_class.call

        expect(result).to be_success
        expect(result.target_positions.size).to eq(1)
        expect(result.target_positions.first.symbol).to eq('GOOGL')
        expect(result.target_positions.first.target_value).to eq(BigDecimal('100000.00'))
      end
    end

    context 'with zero account equity' do
      before do
        create(:quiver_trade, ticker: 'AAPL', transaction_type: 'Purchase', transaction_date: 30.days.ago)
        allow(mock_alpaca_service).to receive(:account_equity).and_return(BigDecimal('0.00'))
      end

      it 'returns empty target positions array' do
        result = described_class.call

        expect(result).to be_success
        expect(result.target_positions).to eq([])
      end
    end

    context 'with negative account equity' do
      before do
        create(:quiver_trade, ticker: 'AAPL', transaction_type: 'Purchase', transaction_date: 30.days.ago)
        allow(mock_alpaca_service).to receive(:account_equity).and_return(BigDecimal('-1000.00'))
      end

      it 'returns empty target positions array' do
        result = described_class.call

        expect(result).to be_success
        expect(result.target_positions).to eq([])
      end
    end

    context 'with blank ticker values in database' do
      before do
        create(:quiver_trade, ticker: 'AAPL', transaction_type: 'Purchase', transaction_date: 30.days.ago)
        # Manually insert a record with empty ticker to simulate data corruption scenario
        insert_sql = <<~SQL.squish
          INSERT INTO quiver_trades (ticker, company, trader_name, trader_source,
                                   transaction_date, transaction_type, trade_size_usd,
                                   disclosed_at, created_at, updated_at)
          VALUES ('', 'Test Company', 'Test Trader', 'test',
                  '#{20.days.ago.to_date}', 'Purchase', '$1000',
                  '#{Time.current}', '#{Time.current}', '#{Time.current}')
        SQL
        QuiverTrade.connection.execute(insert_sql)
        allow(mock_alpaca_service).to receive(:account_equity).and_return(BigDecimal('50000.00'))
      end

      it 'filters out trades with empty tickers' do
        result = described_class.call

        expect(result).to be_success
        expect(result.target_positions.size).to eq(1)
        expect(result.target_positions.first.symbol).to eq('AAPL')
        expect(result.target_positions.first.target_value).to eq(BigDecimal('50000.00'))
      end
    end
  end

  describe 'service integration' do
    context 'when AlpacaService raises an error' do
      before do
        create(:quiver_trade, ticker: 'AAPL', transaction_type: 'Purchase', transaction_date: 30.days.ago)
        allow(mock_alpaca_service).to receive(:account_equity).and_raise(StandardError, 'API error')
      end

      it 'fails when service raises an error' do
        result = described_class.call
        expect(result).to be_failure
        # GLCommand catches the error and makes the command fail
      end
    end
  end

  describe 'target position attributes' do
    before do
      create(:quiver_trade, ticker: 'AAPL', transaction_type: 'Purchase', transaction_date: 30.days.ago)
      allow(mock_alpaca_service).to receive(:account_equity).and_return(BigDecimal('100000.00'))
    end

    it 'creates TargetPosition objects with correct attributes' do
      result = described_class.call

      position = result.target_positions.first
      expect(position.symbol).to eq('AAPL')
      expect(position.asset_type).to eq(:stock)
      expect(position.target_value).to eq(BigDecimal('100000.00'))
      expect(position.details).to eq({})
    end
  end
end
