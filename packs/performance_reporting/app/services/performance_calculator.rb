# frozen_string_literal: true

class PerformanceCalculator
  MIN_DAYS_FOR_SHARPE = 30
  TRADING_DAYS_PER_YEAR = 252

  def initialize(risk_free_rate: 0.045)
    @risk_free_rate = risk_free_rate
  end

  def calculate_sharpe_ratio(daily_returns)
    return nil if daily_returns.nil? || daily_returns.length < MIN_DAYS_FOR_SHARPE

    annualized_return = calculate_annualized_return_from_returns(daily_returns)
    volatility = calculate_volatility(daily_returns)

    return nil if volatility.nil? || volatility.zero?

    ((annualized_return - @risk_free_rate) / volatility).round(4)
  rescue StandardError => e
    Rails.logger.warn("Failed to calculate Sharpe ratio: #{e.message}")
    nil
  end

  def calculate_max_drawdown(equity_values)
    return nil if equity_values.blank?

    peak = equity_values.first.to_f
    max_dd = 0.0

    equity_values.each do |value|
      value_f = value.to_f
      peak = value_f if value_f > peak
      drawdown = ((value_f - peak) / peak * 100).round(4)
      max_dd = drawdown if drawdown < max_dd
    end

    max_dd
  rescue StandardError => e
    Rails.logger.warn("Failed to calculate max drawdown: #{e.message}")
    nil
  end

  def calculate_win_rate(trades)
    return nil if trades.blank?

    winning = trades.count { |t| trade_profitable?(t) }
    ((winning.to_f / trades.length) * 100).round(4)
  rescue StandardError => e
    Rails.logger.warn("Failed to calculate win rate: #{e.message}")
    nil
  end

  def calculate_volatility(daily_returns)
    return nil if daily_returns.nil? || daily_returns.length < MIN_DAYS_FOR_SHARPE

    mean = daily_returns.sum / daily_returns.length
    variance = daily_returns.sum { |r| (r - mean)**2 } / daily_returns.length
    std_dev = Math.sqrt(variance)

    (std_dev * Math.sqrt(TRADING_DAYS_PER_YEAR)).round(4)
  rescue StandardError => e
    Rails.logger.warn("Failed to calculate volatility: #{e.message}")
    nil
  end

  def calculate_calmar_ratio(annualized_return, max_drawdown)
    return nil if max_drawdown.nil? || max_drawdown.zero?

    (annualized_return / max_drawdown.abs).round(4)
  rescue StandardError => e
    Rails.logger.warn("Failed to calculate Calmar ratio: #{e.message}")
    nil
  end

  def annualized_return(equity_start, equity_end, days)
    return nil if equity_start.nil? || equity_end.nil? || days.nil? || days.zero? || equity_start.zero?

    equity_start_f = equity_start.to_f
    equity_end_f = equity_end.to_f

    total_return = (equity_end_f - equity_start_f) / equity_start_f
    years = days.to_f / 365.0

    (((1 + total_return)**(1 / years)) - 1).round(4)
  rescue StandardError => e
    Rails.logger.warn("Failed to calculate annualized return: #{e.message}")
    nil
  end

  private

  def calculate_annualized_return_from_returns(daily_returns)
    return 0.0 if daily_returns.empty?

    geometric_mean = (daily_returns.map { |r| 1 + r }.reduce(:*)**(1.0 / daily_returns.length)) - 1
    (((1 + geometric_mean)**TRADING_DAYS_PER_YEAR) - 1).round(4)
  end

  def trade_profitable?(trade)
    # Simple check: does the trade have a positive realized P&L?
    trade.respond_to?(:realized_pl) && trade.realized_pl&.positive?
  end
end
