# frozen_string_literal: true

# Service to calculate quality scores for politicians based on their trading performance
class PoliticianScorer
  MINIMUM_TRADES_FOR_SCORING = 5
  LOOKBACK_PERIOD_DAYS = 365

  def initialize(politician_profile)
    @politician = politician_profile
  end

  def call
    return default_score unless sufficient_trade_history?

    calculate_score
  end

  private

  attr_reader :politician

  def sufficient_trade_history?
    recent_trades.count >= MINIMUM_TRADES_FOR_SCORING
  end

  def recent_trades
    @recent_trades ||= politician.trades
                                 .where(transaction_date: LOOKBACK_PERIOD_DAYS.days.ago..)
                                 .where(transaction_type: 'Purchase')
  end

  def calculate_score
    # Score formula: (win_rate * 0.6) + (avg_return * 0.4)
    # Normalized to 0-10 scale

    win_rate_component = (calculate_win_rate / 100.0) * 6.0
    return_component = normalize_return(calculate_average_return) * 4.0

    score = win_rate_component + return_component

    # Update politician profile
    politician.update!(
      quality_score: score.round(2),
      total_trades: recent_trades.count,
      winning_trades: count_winning_trades,
      average_return: calculate_average_return.round(2),
      last_scored_at: Time.current
    )

    score.round(2)
  end

  def calculate_win_rate
    winning_count = count_winning_trades
    total_count = recent_trades.count

    return 50.0 if total_count.zero?

    (winning_count.to_f / total_count * 100).round(2)
  end

  def count_winning_trades
    # Simplified: assume a trade is "winning" if the stock is up 5%+ after 30 days
    # In production, this would check actual price data
    # For now, use a heuristic based on transaction patterns

    purchases = recent_trades.group(:ticker).count

    # If a politician bought and never sold, assume it's winning
    # If they sold later, check the time difference
    winning = 0

    purchases.each do |ticker, buy_count|
      sells = politician.trades
                        .where(ticker: ticker, transaction_type: 'Sale')
                        .where(transaction_date: LOOKBACK_PERIOD_DAYS.days.ago..)
                        .count

      # Simple heuristic: no sells = likely winning
      winning += buy_count if sells.zero?
      # If sold, assume 60% of remaining are winners
      winning += ((buy_count - sells) * 0.6).round if sells.positive?
    end

    winning
  end

  def calculate_average_return
    # Simplified calculation: assume average 5-15% return for active traders
    # In production, would calculate actual returns from price data
    # For now, use win rate as proxy

    win_rate = calculate_win_rate

    # Map win rate to expected return
    # 50% win rate = 5% avg return
    # 80% win rate = 15% avg return

    base_return = 5.0
    bonus_return = ((win_rate - 50.0) / 30.0) * 10.0

    [base_return + bonus_return, 0.0].max
  end

  def normalize_return(return_pct)
    # Normalize return percentage to 0-1 scale
    # Assume 0% = 0, 20% = 1.0
    [return_pct / 20.0, 1.0].min
  end

  def default_score
    politician.update!(
      quality_score: 5.0,
      total_trades: recent_trades.count,
      winning_trades: nil,
      average_return: nil,
      last_scored_at: Time.current
    )

    5.0
  end
end
