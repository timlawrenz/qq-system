# frozen_string_literal: true

# AnalysePerformance Command
#
# This command performs the actual business logic of performance analysis.
# It processes trades, fetches market data, and calculates performance metrics.
class AnalysePerformance < GLCommand::Callable
  requires analysis: Analysis
  returns :results

  def call
    trades = Trade.where(
      algorithm_id: analysis.algorithm_id,
      executed_at: analysis.start_date.beginning_of_day..analysis.end_date.end_of_day
    ).order(:executed_at)

    symbols = trades.pluck(:symbol).uniq.sort
    fetch_result = Fetch.call!(
      symbols: symbols,
      start_date: analysis.start_date,
      end_date: analysis.end_date
    )
    stop_and_fail!("Failed to fetch market data: #{fetch_result.error}") unless fetch_result.success?

    context.results = calculate_performance_metrics(trades, analysis.start_date, analysis.end_date)
  end

  private

  def calculate_performance_metrics(trades, start_date, end_date)
    # Build daily portfolio value time series
    portfolio_values = build_portfolio_time_series(trades, start_date, end_date)

    return { error: 'No portfolio data calculated' } if portfolio_values.empty?

    # Calculate key performance metrics
    total_pnl = calculate_total_pnl(portfolio_values)
    returns = calculate_daily_returns(portfolio_values)

    {
      total_pnl: total_pnl,
      total_pnl_percentage: calculate_percentage_return(portfolio_values),
      annualized_return: calculate_annualized_return(returns),
      volatility: calculate_volatility(returns),
      sharpe_ratio: calculate_sharpe_ratio(returns),
      max_drawdown: calculate_max_drawdown(portfolio_values),
      calmar_ratio: calculate_calmar_ratio(returns, portfolio_values),
      win_loss_ratio: calculate_win_loss_ratio(trades),
      portfolio_time_series: portfolio_values,
      calculated_at: Time.current.iso8601
    }
  end

  def build_portfolio_time_series(trades, start_date, end_date)
    portfolio_values = {}
    current_positions = {}
    initial_cash = 100_000.0 # Assume $100k starting capital
    cash = initial_cash

    # Process each day in the date range
    (start_date..end_date).each do |date|
      daily_trades = trades.select { |trade| trade.executed_at.to_date == date }

      # Process trades for this day
      daily_trades.each do |trade|
        trade_value = trade.quantity * trade.price

        if trade.side == 'buy'
          current_positions[trade.symbol] = (current_positions[trade.symbol] || 0) + trade.quantity
          cash -= trade_value
        else # sell
          current_positions[trade.symbol] = (current_positions[trade.symbol] || 0) - trade.quantity
          cash += trade_value
        end
      end

      # Calculate portfolio value using closing prices
      portfolio_value = cash
      current_positions.each do |symbol, quantity|
        next if quantity.zero?

        closing_price = get_closing_price(symbol, date)
        next unless closing_price

        portfolio_value += quantity * closing_price
      end

      portfolio_values[date.iso8601] = portfolio_value.round(2)
    end

    portfolio_values
  end

  def get_closing_price(symbol, date)
    # Get closing price from HistoricalBar cache
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
    (((1 + avg_daily_return)**252) - (1 * 100)).round(4) # 252 trading days per year
  end

  def calculate_volatility(returns)
    return 0.0 if returns.length < 2

    mean = returns.sum / returns.length
    variance = returns.sum { |r| (r - mean)**2 } / (returns.length - 1)
    (Math.sqrt(variance) * Math.sqrt(252) * 100).round(4) # Annualized
  end

  def calculate_sharpe_ratio(returns)
    return 0.0 if returns.empty?

    risk_free_rate = 0.02 / 252 # Assume 2% annual risk-free rate
    excess_returns = returns.map { |r| r - risk_free_rate }

    return 0.0 if excess_returns.empty?

    mean_excess = excess_returns.sum / excess_returns.length
    return 0.0 if mean_excess.zero?

    volatility = calculate_volatility(returns) / 100 / Math.sqrt(252) # Daily volatility
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

  def calculate_win_loss_ratio(trades)
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
