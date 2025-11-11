# frozen_string_literal: true

# Service to detect consensus trades (multiple politicians buying same stock)
class ConsensusDetector
  CONSENSUS_WINDOW_DAYS = 30
  MINIMUM_POLITICIANS_FOR_CONSENSUS = 2

  def initialize(ticker:, lookback_days: 45)
    @ticker = ticker
    @lookback_days = lookback_days
  end

  def call
    {
      is_consensus: consensus?,
      politician_count: unique_politicians.count,
      consensus_strength: consensus_strength,
      politicians: unique_politicians
    }
  end

  def consensus?
    unique_politicians.count >= MINIMUM_POLITICIANS_FOR_CONSENSUS
  end

  private

  attr_reader :ticker, :lookback_days

  def recent_purchases
    @recent_purchases ||= QuiverTrade
                          .where(ticker: ticker)
                          .where(transaction_type: 'Purchase')
                          .where(trader_source: 'congress')
                          .where(transaction_date: lookback_days.days.ago..)
  end

  def unique_politicians
    @unique_politicians ||= recent_purchases.pluck(:trader_name).uniq
  end

  def consensus_strength
    # Calculate strength based on number of politicians and their quality scores
    return 0.0 unless consensus?

    # Base strength from count (2 politicians = 1.0, 3+ = 1.5+)
    count_multiplier = [unique_politicians.count / 2.0, 3.0].min

    # Bonus for high-quality politicians
    quality_bonus = calculate_quality_bonus

    (count_multiplier + quality_bonus).round(2)
  end

  def calculate_quality_bonus
    profiles = PoliticianProfile.where(name: unique_politicians).with_quality_score
    return 0.0 if profiles.empty?

    avg_quality = profiles.average(:quality_score).to_f

    # Quality score 7+ adds bonus, 9+ adds more
    return 0.0 if avg_quality < 7.0
    return 0.3 if avg_quality < 8.0
    return 0.5 if avg_quality < 9.0

    0.7
  end
end
