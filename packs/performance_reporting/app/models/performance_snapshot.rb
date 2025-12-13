# frozen_string_literal: true

# rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

class PerformanceSnapshot < ApplicationRecord
  validates :snapshot_date, :snapshot_type, :strategy_name, presence: true
  validates :snapshot_type, inclusion: { in: %w[daily weekly] }
  validates :snapshot_date, uniqueness: { scope: %i[strategy_name snapshot_type] }

  scope :daily, -> { where(snapshot_type: 'daily') }
  scope :weekly, -> { where(snapshot_type: 'weekly') }
  scope :by_strategy, ->(name) { where(strategy_name: name) }
  scope :between_dates, ->(start_date, end_date) { where(snapshot_date: start_date..end_date) }

  def to_report_hash
    {
      date: snapshot_date.to_s,
      type: snapshot_type,
      strategy: strategy_name,
      equity: total_equity&.to_f,
      pnl: total_pnl&.to_f,
      pnl_pct: total_equity&.positive? ? ((total_pnl / (total_equity - total_pnl)) * 100)&.round(2) : nil,
      sharpe_ratio: sharpe_ratio&.to_f,
      max_drawdown_pct: max_drawdown_pct&.to_f,
      volatility: volatility&.to_f,
      win_rate: win_rate&.to_f,
      total_trades: total_trades,
      winning_trades: winning_trades,
      losing_trades: losing_trades,
      calmar_ratio: calmar_ratio&.to_f,
      metadata: metadata
    }
  end
end
# rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
