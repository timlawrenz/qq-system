# frozen_string_literal: true

# rubocop:disable RSpec/VerifiedDoubles

require 'rails_helper'

RSpec.describe PerformanceCalculator do
  let(:calculator) { described_class.new }

  describe '#calculate_sharpe_ratio' do
    it 'calculates Sharpe ratio with sufficient data' do
      # Daily returns for 90 days (annualized return ~12%, volatility ~15%)
      daily_returns = Array.new(90) { rand(-0.02..0.02) }

      result = calculator.calculate_sharpe_ratio(daily_returns)

      expect(result).not_to be_nil
      expect(result).to be_a(Float)
    end

    it 'returns nil with insufficient data' do
      daily_returns = Array.new(15) { rand(-0.01..0.01) }

      result = calculator.calculate_sharpe_ratio(daily_returns)

      expect(result).to be_nil
    end

    it 'returns nil with empty array' do
      result = calculator.calculate_sharpe_ratio([])

      expect(result).to be_nil
    end
  end

  describe '#calculate_max_drawdown' do
    it 'calculates max drawdown correctly' do
      equity_values = [100_000, 102_000, 98_000, 99_000, 101_000]

      result = calculator.calculate_max_drawdown(equity_values)

      # Peak is 102,000, trough is 98,000
      # Drawdown = (98,000 - 102,000) / 102,000 * 100 = -3.92%
      expect(result).to be_within(0.01).of(-3.92)
    end

    it 'returns 0 for constantly increasing equity' do
      equity_values = [100_000, 105_000, 110_000, 115_000]

      result = calculator.calculate_max_drawdown(equity_values)

      expect(result).to eq(0.0)
    end

    it 'returns nil for empty array' do
      result = calculator.calculate_max_drawdown([])

      expect(result).to be_nil
    end
  end

  describe '#calculate_win_rate' do
    let(:profitable_trade) { double(realized_pl: 100.0) }
    let(:losing_trade) { double(realized_pl: -50.0) }

    it 'calculates win rate correctly' do
      trades = [profitable_trade, profitable_trade, losing_trade, profitable_trade]

      result = calculator.calculate_win_rate(trades)

      # 3 out of 4 trades profitable = 75%
      expect(result).to eq(75.0)
    end

    it 'returns 0 for all losing trades' do
      trades = [losing_trade, losing_trade]

      result = calculator.calculate_win_rate(trades)

      expect(result).to eq(0.0)
    end

    it 'returns nil for empty trades' do
      result = calculator.calculate_win_rate([])

      expect(result).to be_nil
    end
  end

  describe '#calculate_volatility' do
    it 'calculates annualized volatility' do
      # Generate 60 days of returns with known std dev
      daily_returns = Array.new(60) { rand(-0.01..0.01) }

      result = calculator.calculate_volatility(daily_returns)

      expect(result).not_to be_nil
      expect(result).to be_positive
    end

    it 'returns nil with insufficient data' do
      daily_returns = Array.new(20) { 0.001 }

      result = calculator.calculate_volatility(daily_returns)

      expect(result).to be_nil
    end
  end

  describe '#calculate_calmar_ratio' do
    it 'calculates Calmar ratio correctly' do
      annualized_return = 0.15  # 15%
      max_drawdown = -0.05      # -5%

      result = calculator.calculate_calmar_ratio(annualized_return, max_drawdown)

      # 0.15 / 0.05 = 3.0
      expect(result).to eq(3.0)
    end

    it 'returns nil when drawdown is zero' do
      result = calculator.calculate_calmar_ratio(0.10, 0.0)

      expect(result).to be_nil
    end
  end

  describe '#annualized_return' do
    it 'calculates annualized return correctly' do
      equity_start = 100_000
      equity_end = 110_000
      days = 365

      result = calculator.annualized_return(equity_start, equity_end, days)

      # 10% return over 1 year = 10% annualized
      expect(result).to be_within(0.01).of(0.10)
    end

    it 'annualizes correctly for partial years' do
      equity_start = 100_000
      equity_end = 105_000
      days = 182 # ~6 months

      result = calculator.annualized_return(equity_start, equity_end, days)

      # ~5% over 6 months should annualize to ~10%
      expect(result).to be > 0.09
      expect(result).to be < 0.11
    end
  end
end
# rubocop:enable RSpec/VerifiedDoubles
