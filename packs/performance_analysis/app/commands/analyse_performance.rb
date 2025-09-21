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

    calculator = PerformanceMetricsCalculator.new(trades, analysis.start_date, analysis.end_date)
    context.results = calculator.calculate
  end
end
