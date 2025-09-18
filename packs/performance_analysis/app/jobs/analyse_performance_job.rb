# frozen_string_literal: true

# AnalysePerformanceJob
#
# Background job that performs the actual performance analysis calculations.
# It orchestrates data fetching, trade processing, and metric calculations.
class AnalysePerformanceJob < ApplicationJob
  def perform(analysis_id)
    analysis = Analysis.find(analysis_id)
    analysis.start!

    # Get all trades for the algorithm within the analysis date range
    trades = Trade.where(
      algorithm_id: analysis.algorithm_id,
      executed_at: analysis.start_date.beginning_of_day..analysis.end_date.end_of_day
    ).order(:executed_at)

    if trades.empty?
      analysis.mark_as_failed!
      return
    end

    # Determine required symbols and ensure market data is cached
    symbols = trades.pluck(:symbol).uniq.sort
    fetch_result = Fetch.call!(
      symbols: symbols,
      start_date: analysis.start_date,
      end_date: analysis.end_date
    )

    unless fetch_result.success?
      Rails.logger.error("Failed to fetch market data: #{fetch_result.error}")
      analysis.mark_as_failed!
      return
    end

    # Process trades and calculate performance metrics
    results = calculate_performance_metrics(trades, analysis.start_date, analysis.end_date)

    # Store results and mark as completed
    analysis.update!(results: results)
    analysis.complete!
  rescue StandardError => e
    Rails.logger.error("AnalysePerformanceJob failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    analysis = Analysis.find(analysis_id)
    analysis.mark_as_failed! if analysis.status != 'failed'
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
    profitable_trades = 0
    losing_trades = 0
    current_positions = {}

    trades.each do |trade|
      symbol = trade.symbol
      current_positions[symbol] ||= { quantity: 0, avg_price: 0 }

      if trade.side == 'buy'
        # Update average price for position
        total_quantity = current_positions[symbol][:quantity] + trade.quantity
        if total_quantity.positive?
          current_positions[symbol][:avg_price] = (
            (current_positions[symbol][:quantity] * current_positions[symbol][:avg_price]) +
            (trade.quantity * trade.price)
          ) / total_quantity
        end
        current_positions[symbol][:quantity] = total_quantity
      else # sell
        if current_positions[symbol][:quantity].positive?
          # Calculate P&L for this sale
          pnl = trade.quantity * (trade.price - current_positions[symbol][:avg_price])

          if pnl.positive?
            profitable_trades += 1
          elsif pnl.negative?
            losing_trades += 1
          end
        end

        current_positions[symbol][:quantity] -= trade.quantity
      end
    end

    return 0.0 if losing_trades.zero?

    (profitable_trades.to_f / losing_trades).round(4)
  end
end
