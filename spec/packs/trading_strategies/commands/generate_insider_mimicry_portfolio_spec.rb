# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingStrategies::GenerateInsiderMimicryPortfolio do
  let(:total_equity) { 100_000.0 }

  def create_insider_trade(attrs = {})
    QuiverTrade.create!(
      {
        ticker: 'AAPL',
        trader_name: 'Default Insider',
        trader_source: 'insider',
        transaction_type: 'Purchase',
        transaction_date: 5.days.ago.to_date,
        trade_size_usd: '$20,000',
        relationship: 'CEO'
      }.merge(attrs)
    )
  end

  describe '.call' do
    context 'with valid inputs and basic data' do
      it 'builds target positions from insider purchases only' do
        create_insider_trade(ticker: 'AAPL', trade_size_usd: '$20,000', relationship: 'CEO')
        create_insider_trade(ticker: 'MSFT', trade_size_usd: '$30,000', relationship: 'CFO')

        # Non-insider and non-purchase trades should be ignored
        QuiverTrade.create!(
          ticker: 'TSLA',
          trader_name: 'Some Politician',
          trader_source: 'congress',
          transaction_type: 'Purchase',
          transaction_date: 5.days.ago.to_date,
          trade_size_usd: '$50,000',
          relationship: nil
        )

        result = described_class.call(total_equity: total_equity)

        expect(result).to be_success
        expect(result.target_positions).not_to be_empty
        symbols = result.target_positions.map(&:symbol)
        expect(symbols).to contain_exactly('AAPL', 'MSFT')

        expect(result.stats[:total_trades]).to eq(2)
        expect(result.stats[:trades_after_filters]).to eq(2)
        expect(result.stats[:unique_tickers]).to eq(2)
      end
    end

    context 'with transaction value and executive filters' do
      it 'applies min_transaction_value and executive_only filters' do
        # Below threshold trade
        create_insider_trade(ticker: 'SMALL', trade_size_usd: '$5,000', relationship: 'CEO')

        # Above threshold but non-executive
        create_insider_trade(ticker: 'MID', trade_size_usd: '$20,000', relationship: 'Director')

        # Above threshold and executive
        create_insider_trade(ticker: 'BIG', trade_size_usd: '$50,000', relationship: 'Chief Executive Officer')

        result = described_class.call(
          total_equity: total_equity,
          min_transaction_value: 10_000,
          executive_only: true
        )

        expect(result).to be_success
        symbols = result.target_positions.map(&:symbol)

        # Only BIG should pass both filters
        expect(symbols).to contain_exactly('BIG')
        expect(result.stats[:total_trades]).to eq(3)
        expect(result.stats[:trades_after_filters]).to eq(1)
        expect(result.stats[:unique_tickers]).to eq(1)
      end

      it 'includes non-executives when executive_only is false' do
        create_insider_trade(ticker: 'MID', trade_size_usd: '$20,000', relationship: 'Director')
        create_insider_trade(ticker: 'BIG', trade_size_usd: '$50,000', relationship: 'CEO')

        result = described_class.call(
          total_equity: total_equity,
          min_transaction_value: 10_000,
          executive_only: false
        )

        expect(result).to be_success
        symbols = result.target_positions.map(&:symbol)
        expect(symbols).to contain_exactly('MID', 'BIG')
        expect(result.stats[:trades_after_filters]).to eq(2)
      end
    end

    context 'with missing equity' do
      it 'fails when total_equity is missing or non-positive' do
        result = described_class.call(total_equity: nil)

        expect(result).to be_failure
        expect(result.full_error_message).to include('total_equity parameter is required and must be positive')
      end
    end
  end
end
