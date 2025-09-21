# frozen_string_literal: true

# PerformanceMetricsCalculator Service
#
# This service encapsulates the business logic for calculating performance metrics.
# It processes trades and market data to generate a comprehensive analysis.
class PerformanceMetricsCalculator
  def initialize(trades, start_date, end_date)
    @trades = trades
    @start_date = start_date
    @end_date = end_date
  end

  def calculate
    # Build daily portfolio value time series
    portfolio_values = build_portfolio_time_series

    return { error: 'No portfolio data calculated' } if portfolio_values.empty?

    # Calculate key performance metrics
    returns = calculate_daily_returns(portfolio_values)

    {
      total_pnl: calculate_total_pnl(portfolio_values),
      total_pnl_percentage: calculate_percentage_return(portfolio_values),
      annualized_return: calculate_annualized_return(returns),
      volatility: calculate_volatility(returns),
      sharpe_ratio: calculate_sharpe_ratio(returns),
      max_drawdown: calculate_max_drawdown(portfolio_values),
      calmar_ratio: calculate_calmar_ratio(returns, portfolio_values),
      win_loss_ratio: calculate_win_loss_ratio,
      portfolio_time_series: portfolio_values,
      calculated_at: Time.current.iso8601
    }
  end

  private

  attr_reader :trades, :start_date, :end_date

  def build_portfolio_time_series
    portfolio_values = {}
    current_positions = {}
    cash = 100_000.0 # Assume $100k starting capital

    (start_date..end_date).each do |date|
      process_daily_trades(date, current_positions, cash)
      portfolio_values[date.iso8601] = calculate_daily_portfolio_value(date, current_positions, cash).round(2)
    end

    portfolio_values
  end

  def process_daily_trades(date, current_positions, cash)
    daily_trades = trades.select { |trade| trade.executed_at.to_date == date }

    daily_trades.each do |trade|
      trade_value = trade.quantity * trade.price
      symbol = trade.symbol
      quantity_change = trade.side == 'buy' ? trade.quantity : -trade.quantity
      current_positions[symbol] = (current_positions[symbol] || 0) + quantity_change
      cash += (trade.side == 'buy' ? -trade_value : trade_value)
    end
  end

  def calculate_daily_portfolio_value(date, current_positions, cash)
    portfolio_value = cash
    current_positions.each do |symbol, quantity|
      next if quantity.zero?

      closing_price = get_closing_price(symbol, date)
      portfolio_value += quantity * closing_price if closing_price
    end
    portfolio_value
  end

  def get_closing_price(symbol, date)
    bar = HistoricalBar.find_by(symbol: symbol, timestamp: date)
    bar&.close
  end

  def calculate_total_pnl(portfolio_values)
    return 0.0 if portfolio_values.empty?

    values = portfolio_values.values
    values.last - values.first
  end

  def calculate_percentage_return(portfolio_values)
    return 0.0 if portfolio_values.empty?

    values = portfolio_values.values
    return 0.0 if values.first.zero?

    ((values.last - values.first) / values.first * 100).round(4)
  end

  def calculate_daily_returns(portfolio_values)
    values = portfolio_values.values
    return [] if values.length < 2

    returns = []
    (1...values.length).each do |i|
      prev_value = values[i - 1]
      curr_value = values[i]
      returns << ((curr_value - prev_value) / prev_value) if prev_value.positive?
    end
    returns
  end

  def calculate_annualized_return(returns)
    return 0.0 if returns.empty?

    avg_daily_return = returns.sum / returns.length
    (((1 + avg_daily_return)**252) - 1) * 100
  end

  def calculate_volatility(returns)
    return 0.0 if returns.length < 2

    mean = returns.sum / returns.length
    variance = returns.sum { |r| (r - mean)**2 } / (returns.length - 1)
    (Math.sqrt(variance) * Math.sqrt(252) * 100).round(4)
  end

  def calculate_sharpe_ratio(returns)
    return 0.0 if returns.empty?

    risk_free_rate = 0.02 / 252
    excess_returns = returns.map { |r| r - risk_free_rate }
    return 0.0 if excess_returns.empty?

    mean_excess = excess_returns.sum / excess_returns.length
    return 0.0 if mean_excess.zero?

    volatility = calculate_volatility(returns) / 100 / Math.sqrt(252)
    return 0.0 if volatility.zero?

    (mean_excess / volatility * Math.sqrt(252)).round(4)
  end

  def calculate_max_drawdown(portfolio_values)
    values = portfolio_values.values
    return 0.0 if values.length < 2

    peak = values.first
    max_drawdown = 0.0

    values.each do |value|
      peak = [peak, value].max
      drawdown = (peak - value) / peak
      max_drawdown = [max_drawdown, drawdown].max
    end

    (max_drawdown * 100).round(4)
  end

  def calculate_calmar_ratio(returns, portfolio_values)
    annualized_return = calculate_annualized_return(returns)
    max_drawdown = calculate_max_drawdown(portfolio_values)
    return 0.0 if max_drawdown.zero?

    (annualized_return / max_drawdown).round(4)
  end

  def calculate_win_loss_ratio
    profitable_losing_counts = { profitable: 0, losing: 0 }
    current_positions = {}

    trades.each do |trade|
      process_trade_for_win_loss(trade, current_positions, profitable_losing_counts)
    end

    losing_trades = profitable_losing_counts[:losing]
    return 0.0 if losing_trades.zero?

    (profitable_losing_counts[:profitable].to_f / losing_trades).round(4)
  end

  def process_trade_for_win_loss(trade, positions, counts)
    symbol = trade.symbol
    positions[symbol] ||= { quantity: 0, avg_price: 0 }

    if trade.side == 'buy'
      update_average_price_on_buy(positions[symbol], trade)
    else # sell
      calculate_pnl_on_sell(positions[symbol], trade, counts)
    end

    positions[symbol][:quantity] += (trade.side == 'buy' ? trade.quantity : -trade.quantity)
  end

  def update_average_price_on_buy(position, trade)
    total_quantity = position[:quantity] + trade.quantity
    return unless total_quantity.positive?

    position[:avg_price] =
      ((position[:quantity] * position[:avg_price]) + (trade.quantity * trade.price)) / total_quantity
  end

  def calculate_pnl_on_sell(position, trade, counts)
    return unless position[:quantity].positive?

    pnl = trade.quantity * (trade.price - position[:avg_price])
    if pnl.positive?
      counts[:profitable] += 1
    elsif pnl.negative?
      counts[:losing] += 1
    end
  end
end
