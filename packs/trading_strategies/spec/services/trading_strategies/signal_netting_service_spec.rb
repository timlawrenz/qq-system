# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingStrategies::SignalNettingService do
  let(:strategy_weights) do
    {
      'StrategyA' => 0.5,
      'StrategyB' => 0.5,
      'StrategyC' => 0.0 # Zero weight
    }
  end

  subject { described_class.new(signals: signals, strategy_weights: strategy_weights) }

  describe '#call' do
    context 'with conflicting signals' do
      let(:signals) do
        [
          TradingStrategies::TradingSignal.new(ticker: 'AAPL', strategy_name: 'StrategyA', score: 1.0),
          TradingStrategies::TradingSignal.new(ticker: 'AAPL', strategy_name: 'StrategyB', score: -1.0)
        ]
      end

      it 'nets to zero' do
        result = subject.call
        expect(result['AAPL']).to eq(0.0)
      end
    end

    context 'with reinforcing signals' do
      let(:signals) do
        [
          TradingStrategies::TradingSignal.new(ticker: 'MSFT', strategy_name: 'StrategyA', score: 0.5),
          TradingStrategies::TradingSignal.new(ticker: 'MSFT', strategy_name: 'StrategyB', score: 1.0)
        ]
      end

      it 'calculates weighted average' do
        # (0.5 * 0.5) + (1.0 * 0.5) = 0.25 + 0.5 = 0.75
        # Total weight = 1.0
        # Result = 0.75
        result = subject.call
        expect(result['MSFT']).to eq(0.75)
      end
    end

    context 'with different weights' do
      let(:strategy_weights) do
        {
          'StrategyA' => 0.8,
          'StrategyB' => 0.2
        }
      end

      let(:signals) do
        [
          TradingStrategies::TradingSignal.new(ticker: 'GOOG', strategy_name: 'StrategyA', score: 1.0),
          TradingStrategies::TradingSignal.new(ticker: 'GOOG', strategy_name: 'StrategyB', score: -1.0)
        ]
      end

      it 'favors the higher weighted strategy' do
        # (1.0 * 0.8) + (-1.0 * 0.2) = 0.8 - 0.2 = 0.6
        # Total weight = 1.0
        # Result = 0.6
        result = subject.call
        expect(result['GOOG']).to be_within(0.001).of(0.6)
      end
    end

    context 'with zero weight strategy' do
      let(:signals) do
        [
          TradingStrategies::TradingSignal.new(ticker: 'AMZN', strategy_name: 'StrategyA', score: 1.0),
          TradingStrategies::TradingSignal.new(ticker: 'AMZN', strategy_name: 'StrategyC', score: -1.0) # Should be ignored
        ]
      end

      it 'ignores the zero weight signal' do
        # (1.0 * 0.5) + (-1.0 * 0.0) = 0.5
        # Total weight = 0.5
        # Result = 1.0
        result = subject.call
        expect(result['AMZN']).to eq(1.0)
      end
    end

    context 'with missing weight strategy' do
      let(:signals) do
        [
          TradingStrategies::TradingSignal.new(ticker: 'TSLA', strategy_name: 'StrategyA', score: 1.0),
          TradingStrategies::TradingSignal.new(ticker: 'TSLA', strategy_name: 'UnknownStrategy', score: -1.0)
        ]
      end

      it 'ignores the unknown strategy' do
        result = subject.call
        expect(result['TSLA']).to eq(1.0)
      end
    end

    context 'with multiple tickers' do
      let(:signals) do
        [
          TradingStrategies::TradingSignal.new(ticker: 'AAPL', strategy_name: 'StrategyA', score: 1.0),
          TradingStrategies::TradingSignal.new(ticker: 'MSFT', strategy_name: 'StrategyB', score: -0.5)
        ]
      end

      it 'calculates scores for each ticker independently' do
        result = subject.call
        expect(result['AAPL']).to eq(1.0) # Only StrategyA (0.5 weight) -> 1.0
        expect(result['MSFT']).to eq(-0.5) # Only StrategyB (0.5 weight) -> -0.5
      end
    end
  end
end
