# frozen_string_literal: true

class BenchmarkComparator
  SPY_SYMBOL = 'SPY'
  CACHE_DURATION = 1.day

  def initialize(alpaca_service: AlpacaService.new)
    @alpaca_service = alpaca_service
  end

  def fetch_spy_returns(start_date, end_date)
    bars = fetch_spy_bars(start_date, end_date)
    return nil if bars.blank?

    calculate_daily_returns(bars)
  rescue StandardError => e
    Rails.logger.error("Failed to fetch SPY returns: #{e.message}")
    nil
  end

  def calculate_alpha(portfolio_return, spy_return)
    return nil if portfolio_return.nil? || spy_return.nil?

    (portfolio_return - spy_return).round(4)
  end

  def calculate_beta(portfolio_returns, spy_returns)
    return nil if portfolio_returns.nil? || spy_returns.nil?
    return nil if portfolio_returns.empty? || spy_returns.empty?
    return nil if portfolio_returns.length != spy_returns.length

    covariance = calculate_covariance(portfolio_returns, spy_returns)
    variance = calculate_variance(spy_returns)

    return nil if variance.nil? || variance.zero?

    (covariance / variance).round(4)
  rescue StandardError => e
    Rails.logger.error("Failed to calculate beta: #{e.message}")
    nil
  end

  private

  def fetch_spy_bars(start_date, end_date)
    # Check Rails cache first
    cache_key = "spy_bars_#{start_date}_#{end_date}"
    cached = Rails.cache.read(cache_key)
    return cached if cached.present?

    # Fetch from Alpaca
    bars = @alpaca_service.get_bars(
      symbol: SPY_SYMBOL,
      timeframe: '1Day',
      start_date: start_date.to_s,
      end_date: end_date.to_s
    )

    # Cache the results
    Rails.cache.write(cache_key, bars, expires_in: CACHE_DURATION) if bars.present?

    bars
  rescue StandardError => e
    Rails.logger.error("Failed to fetch SPY bars from Alpaca: #{e.message}")
    nil
  end

  def calculate_daily_returns(bars)
    return [] if bars.length < 2

    bars.each_cons(2).filter_map do |prev_bar, curr_bar|
      prev_close = prev_bar[:close] || prev_bar['close']
      curr_close = curr_bar[:close] || curr_bar['close']

      next nil if prev_close.nil? || curr_close.nil? || prev_close.zero?

      ((curr_close - prev_close) / prev_close).to_f
    end
  end

  def calculate_covariance(returns_a, returns_b)
    n = returns_a.length
    mean_a = returns_a.sum / n
    mean_b = returns_b.sum / n

    returns_a.zip(returns_b).sum do |a, b|
      (a - mean_a) * (b - mean_b)
    end / n
  end

  def calculate_variance(returns)
    n = returns.length
    mean = returns.sum / n

    returns.sum { |r| (r - mean)**2 } / n
  end
end
