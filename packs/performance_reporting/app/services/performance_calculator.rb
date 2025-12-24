# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength
class PerformanceCalculator
  Fill = Data.define(:symbol, :side, :qty, :price, :time)
  # We can compute a *rough* Sharpe/volatility with less than 30 trading days,
  # but still treat it as "limited data" in reporting.
  MIN_DAYS_FOR_SHARPE = 5
  WARN_DAYS_FOR_SHARPE = 30
  TRADING_DAYS_PER_YEAR = 252

  def initialize(risk_free_rate: 0.045)
    @risk_free_rate = risk_free_rate
  end

  MAX_ABS_SHARPE = 100.0
  MIN_VOLATILITY_FLOOR = 1e-6

  def calculate_sharpe_ratio(daily_returns)
    return nil if daily_returns.nil? || daily_returns.length < MIN_DAYS_FOR_SHARPE

    annualized_return = calculate_annualized_return_from_returns(daily_returns)
    volatility = calculate_volatility(daily_returns)

    return nil if volatility.nil? || volatility.abs < MIN_VOLATILITY_FLOOR

    sharpe = (annualized_return - @risk_free_rate) / volatility
    return nil if sharpe.nan? || sharpe.infinite?

    if sharpe.abs > MAX_ABS_SHARPE
      Rails.logger.warn("Sharpe ratio out of bounds (#{sharpe}); returning nil")
      return nil
    end

    sharpe.round(4)
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

    known = trades.select { |t| trade_profitable?(t).in?([true, false]) }
    return nil if known.empty?

    winning = known.count { |t| trade_profitable?(t) == true }
    ((winning.to_f / known.length) * 100).round(4)
  rescue StandardError => e
    Rails.logger.warn("Failed to calculate win rate: #{e.message}")
    nil
  end

  def realized_trade_outcomes_from_fills(fills)
    fills = Array(fills).map do |f|
      next f if f.is_a?(Fill)

      Fill.new(f[:symbol], f[:side], f[:qty], f[:price], f[:time])
    end

    per_symbol = fills.sort_by(&:time).group_by(&:symbol)

    per_symbol.flat_map do |_symbol, sym_fills|
      realized_roundtrip_pnls(sym_fills)
    end
  rescue StandardError => e
    Rails.logger.warn("Failed to compute realized trade outcomes: #{e.message}")
    []
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength
  def realized_roundtrip_pnls(fills)
    position_qty = 0.0
    avg_price = 0.0
    realized = 0.0
    outcomes = []

    fills.each do |f|
      qty = f.qty.to_f
      price = f.price.to_f
      side = f.side.to_s

      if side == 'buy'
        if position_qty >= 0
          new_qty = position_qty + qty
          avg_price = ((avg_price * position_qty) + (price * qty)) / new_qty if new_qty.positive?
          position_qty = new_qty
        else
          cover_qty = [qty, position_qty.abs].min
          realized += cover_qty * (avg_price - price)
          position_qty += cover_qty

          leftover = qty - cover_qty
          if leftover.positive?
            position_qty = leftover
            avg_price = price
          end
        end
      elsif side == 'sell'
        if position_qty <= 0
          new_abs = position_qty.abs + qty
          avg_price = ((avg_price * position_qty.abs) + (price * qty)) / new_abs if new_abs.positive?
          position_qty -= qty
        else
          sell_qty = [qty, position_qty].min
          realized += sell_qty * (price - avg_price)
          position_qty -= sell_qty
          leftover = qty - sell_qty
          if leftover.positive?
            position_qty = -leftover
            avg_price = price
          end
        end
      end

      next unless position_qty.abs < 1e-9

      outcomes << realized if realized.abs.positive?
      realized = 0.0
      avg_price = 0.0
      position_qty = 0.0
    end

    outcomes
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength

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

  MAX_ABS_CALMAR = 1000.0
  MIN_DRAWDOWN_FLOOR = 1e-6

  def calculate_calmar_ratio(annualized_return, max_drawdown)
    return nil if max_drawdown.nil? || max_drawdown.abs < MIN_DRAWDOWN_FLOOR

    calmar = annualized_return.to_f / max_drawdown.abs
    return nil if calmar.nan? || calmar.infinite?

    if calmar.abs > MAX_ABS_CALMAR
      Rails.logger.warn("Calmar ratio out of bounds (#{calmar}); returning nil")
      return nil
    end

    calmar.round(4)
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

  private :realized_roundtrip_pnls

  private

  def calculate_annualized_return_from_returns(daily_returns)
    return 0.0 if daily_returns.empty?

    geometric_mean = (daily_returns.map { |r| 1 + r }.reduce(:*)**(1.0 / daily_returns.length)) - 1
    (((1 + geometric_mean)**TRADING_DAYS_PER_YEAR) - 1).round(4)
  end

  # rubocop:disable Style/ReturnNilInPredicateMethodDefinition
  def trade_profitable?(trade)
    # Alpaca order payloads don't include realized P&L; treat profitability as unknown.
    return nil unless trade.respond_to?(:realized_pl) && trade.realized_pl.present?

    trade.realized_pl.positive?
  end
  # rubocop:enable Style/ReturnNilInPredicateMethodDefinition
end
# rubocop:enable Metrics/ClassLength
