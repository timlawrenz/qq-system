# frozen_string_literal: true

# LobbyingRankingService
#
# Simplified service for ranking stocks by lobbying spend.
# This is Phase 2a - MVP version that ranks by absolute spend without market cap normalization.
#
# Academic Rationale:
# - High lobbying spend correlates with political influence
# - Influence correlates with favorable outcomes (contracts, regulations, tax breaks)
# - Favorable outcomes correlate with stock returns
#
# Future Enhancement (Phase 2b):
# - Add market cap normalization: intensity = lobbying_spend / market_cap
# - This controls for company size (e.g., $10M lobbying for $1B company vs $1T company)
#
# Usage:
#   service = LobbyingRankingService.new(quarter: 'Q4 2025')
#   rankings = service.rank_by_lobbying
#   # => { 'GOOGL' => { spend: 4815000.0, rank: 1, percentile: 100 }, ... }
class LobbyingRankingService
  # rubocop:disable Metrics/AbcSize
  attr_reader :quarter

  def initialize(quarter:)
    @quarter = quarter
  end

  # Rank all tickers by lobbying spend for the quarter
  # Returns hash with spend, rank, percentile, and z-score
  #
  # @return [Hash<String, Hash>] Ticker to ranking data
  def rank_by_lobbying
    # Get quarterly totals
    totals = LobbyingExpenditure.quarterly_totals(@quarter)

    return {} if totals.empty?

    # Sort by spend (descending)
    sorted = totals.sort_by { |_ticker, amount| -amount }

    # Calculate statistics
    amounts = sorted.map { |_, amount| amount }
    mean = amounts.sum.to_f / amounts.size
    std_dev = calculate_std_dev(amounts, mean)

    # Build rankings
    rankings = {}
    sorted.each_with_index do |(ticker, amount), index|
      rankings[ticker] = {
        spend: amount,
        rank: index + 1,
        percentile: ((sorted.size - index).to_f / sorted.size * 100).round(1),
        z_score: std_dev.positive? ? ((amount - mean) / std_dev).round(2) : 0.0
      }
    end

    rankings
  end

  # Get top N lobbying spenders
  #
  # @param limit [Integer] Number of top spenders to return
  # @return [Array<String>] Array of ticker symbols
  def top_spenders(limit: 10)
    rank_by_lobbying
      .sort_by { |_ticker, data| data[:rank] }
      .first(limit)
      .map(&:first)
  end

  # Get bottom N lobbying spenders (or non-lobbying stocks)
  #
  # @param limit [Integer] Number of bottom spenders to return
  # @return [Array<String>] Array of ticker symbols
  def bottom_spenders(limit: 10)
    rank_by_lobbying
      .sort_by { |_ticker, data| -data[:rank] }
      .first(limit)
      .map(&:first)
  end

  # Get quintile breakpoints
  # Returns the spend amounts at 20%, 40%, 60%, 80% percentiles
  #
  # @return [Hash] Quintile breakpoints
  def quintile_breakpoints
    rankings = rank_by_lobbying
    return {} if rankings.empty?

    sorted_amounts = rankings.values.pluck(:spend).sort.reverse
    size = sorted_amounts.size

    {
      q1_min: sorted_amounts[0], # Top 20%
      q1_max: sorted_amounts[(size * 0.2).floor - 1],
      q2_min: sorted_amounts[(size * 0.2).floor],
      q2_max: sorted_amounts[(size * 0.4).floor - 1],
      q3_min: sorted_amounts[(size * 0.4).floor],
      q3_max: sorted_amounts[(size * 0.6).floor - 1],
      q4_min: sorted_amounts[(size * 0.6).floor],
      q4_max: sorted_amounts[(size * 0.8).floor - 1],
      q5_min: sorted_amounts[(size * 0.8).floor],
      q5_max: sorted_amounts[-1] # Bottom 20%
    }
  end

  # Assign quintile for each ticker (1 = top 20%, 5 = bottom 20%)
  #
  # @return [Hash<String, Integer>] Ticker to quintile mapping
  def assign_quintiles
    rankings = rank_by_lobbying
    size = rankings.size
    quintile_size = (size / 5.0).ceil

    quintiles = {}
    rankings.sort_by { |_ticker, data| data[:rank] }.each_with_index do |(ticker, _data), index|
      quintile = (index / quintile_size) + 1
      quintile = 5 if quintile > 5 # Cap at quintile 5
      quintiles[ticker] = quintile
    end

    quintiles
  end

  private

  def calculate_std_dev(values, mean)
    return 0.0 if values.size <= 1

    variance = values.sum { |v| (v - mean)**2 } / values.size
    Math.sqrt(variance)
  end
  # rubocop:enable Metrics/AbcSize
end
