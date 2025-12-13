# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize

class GeneratePerformanceReport < GLCommand::Callable
  requires :start_date, :end_date, :strategy_name

  returns :report_hash, :file_path, :snapshot_id

  def call
    Rails.logger.info('=== Starting Performance Report Generation ===')

    @start_date = parse_date(context.start_date) || default_start_date
    @end_date = parse_date(context.end_date) || Date.current
    @strategy_name = context.strategy_name || 'Enhanced Congressional'

    Rails.logger.info("Period: #{@start_date} to #{@end_date}")
    Rails.logger.info("Strategy: #{@strategy_name}")

    # Calculate performance metrics
    Rails.logger.info('Step 1: Calculating metrics...')
    metrics = calculate_metrics
    Rails.logger.info("Metrics calculated: #{metrics.keys}")

    # Create snapshot record
    Rails.logger.info('Step 2: Creating snapshot...')
    snapshot = create_snapshot(metrics)
    context.snapshot_id = snapshot.id
    Rails.logger.info("Snapshot created: #{snapshot.id}")

    # Build full report hash
    Rails.logger.info('Step 3: Building report hash...')
    report = build_report_hash(metrics, snapshot)
    context.report_hash = report
    Rails.logger.info('Report hash built')

    # Save report to file
    Rails.logger.info('Step 4: Saving to file...')
    file_path = save_report_to_file(report)
    context.file_path = file_path

    Rails.logger.info("Performance report generated: #{file_path}")
  rescue StandardError => e
    Rails.logger.error("Performance report generation failed: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    fail!(e.message)
  end

  def rollback
    # Clean up created snapshot if it exists
    if defined?(context.snapshot_id) && context.snapshot_id.present?
      PerformanceSnapshot.find_by(id: context.snapshot_id)&.destroy
      Rails.logger.info("Rolled back performance snapshot: #{context.snapshot_id}")
    end

    # Clean up created file if it exists
    return unless defined?(context.file_path) && context.file_path.present? && File.exist?(context.file_path)

    File.delete(context.file_path)
    Rails.logger.info("Deleted report file: #{context.file_path}")
  end

  private

  def parse_date(value)
    return nil if value.nil?
    return value if value.is_a?(Date)

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def default_start_date
    # Default to 30 days ago or first trade date, whichever is later
    earliest_trade = AlpacaOrder.order(:created_at).first
    earliest_date = earliest_trade&.created_at&.to_date || 30.days.ago.to_date

    [earliest_date, 30.days.ago.to_date].max
  end

  def calculate_metrics
    alpaca_service = AlpacaService.new
    calculator = PerformanceCalculator.new
    comparator = BenchmarkComparator.new(alpaca_service: alpaca_service)

    # Fetch account equity history
    equity_history = alpaca_service.account_equity_history(
      start_date: @start_date,
      end_date: @end_date
    )

    # Fetch all closed trades in the period
    trades = AlpacaOrder.where(created_at: @start_date..@end_date)
                        .where(status: 'filled')

    # Calculate daily returns
    daily_returns = calculate_daily_returns(equity_history)

    # Calculate core metrics
    equity_start = equity_history.first&.dig(:equity) || 100_000
    equity_end = equity_history.last&.dig(:equity) || alpaca_service.account_equity
    trading_days = (@end_date - @start_date).to_i.clamp(1, Float::INFINITY)

    {
      equity_history: equity_history,
      equity_start: equity_start,
      equity_end: equity_end,
      total_pnl: equity_end - equity_start,
      daily_returns: daily_returns,
      sharpe_ratio: calculator.calculate_sharpe_ratio(daily_returns),
      max_drawdown: calculator.calculate_max_drawdown(equity_history.pluck(:equity)),
      volatility: calculator.calculate_volatility(daily_returns),
      win_rate: calculator.calculate_win_rate(trades.to_a),
      total_trades: trades.count,
      winning_trades: count_winning_trades(trades),
      losing_trades: count_losing_trades(trades),
      annualized_return: calculator.annualized_return(equity_start, equity_end, trading_days),
      calmar_ratio: nil, # Will calculate after we have annualized_return and max_drawdown
      spy_returns: comparator.fetch_spy_returns(@start_date, @end_date),
      calculator: calculator,
      comparator: comparator
    }
  end

  def calculate_daily_returns(equity_history)
    return [] if equity_history.length < 2

    equity_history.each_cons(2).filter_map do |prev, curr|
      prev_equity = prev[:equity].to_f
      curr_equity = curr[:equity].to_f

      next nil if prev_equity.zero?

      (curr_equity - prev_equity) / prev_equity
    end
  end

  def count_winning_trades(trades)
    trades.count { |t| trade_profitable?(t) }
  end

  def count_losing_trades(trades)
    trades.count { |t| !trade_profitable?(t) }
  end

  def trade_profitable?(trade)
    # Simplified: check if we have realized P&L
    # TODO: Implement proper P&L calculation when available
    trade.respond_to?(:realized_pl) && trade.realized_pl&.positive?
  end

  def create_snapshot(metrics)
    # Calculate Calmar ratio now that we have both values
    calmar = metrics[:calculator].calculate_calmar_ratio(
      metrics[:annualized_return] || 0.0,
      metrics[:max_drawdown]
    )

    PerformanceSnapshot.create!(
      snapshot_date: @end_date,
      snapshot_type: :weekly, # Default to weekly for now
      strategy_name: @strategy_name,
      total_equity: metrics[:equity_end],
      total_pnl: metrics[:total_pnl],
      sharpe_ratio: metrics[:sharpe_ratio],
      max_drawdown_pct: metrics[:max_drawdown],
      volatility: metrics[:volatility],
      win_rate: metrics[:win_rate],
      total_trades: metrics[:total_trades],
      winning_trades: metrics[:winning_trades],
      losing_trades: metrics[:losing_trades],
      calmar_ratio: calmar,
      metadata: build_metadata(metrics)
    )
  end

  def build_metadata(metrics)
    {
      period: {
        start_date: @start_date.to_s,
        end_date: @end_date.to_s,
        trading_days: metrics[:daily_returns]&.length || 0
      },
      warnings: build_warnings(metrics)
    }
  end

  def build_warnings(metrics)
    warnings = []

    if metrics[:daily_returns].nil? || metrics[:daily_returns].length < PerformanceCalculator::MIN_DAYS_FOR_SHARPE
      warnings << "Limited data available (#{metrics[:daily_returns]&.length || 0} days)"
    end

    warnings << 'No trades executed in this period' if metrics[:total_trades].zero?

    warnings
  end

  def build_report_hash(metrics, snapshot)
    report = {
      report_date: @end_date.to_s,
      report_type: 'weekly',
      period: snapshot.metadata['period'],
      strategy: {
        name: @strategy_name,
        total_equity: metrics[:equity_end]&.to_f&.round(2),
        total_pnl: metrics[:total_pnl]&.to_f&.round(2),
        pnl_pct: calculate_pnl_percentage(metrics),
        sharpe_ratio: metrics[:sharpe_ratio],
        max_drawdown_pct: metrics[:max_drawdown],
        volatility: metrics[:volatility],
        win_rate: metrics[:win_rate],
        total_trades: metrics[:total_trades],
        winning_trades: metrics[:winning_trades],
        losing_trades: metrics[:losing_trades],
        calmar_ratio: snapshot.calmar_ratio&.to_f
      },
      warnings: snapshot.metadata['warnings']
    }

    # Add SPY benchmark comparison if available
    report[:benchmark] = build_benchmark_comparison(metrics) if metrics[:spy_returns].present?

    report
  end

  def calculate_pnl_percentage(metrics)
    return nil if metrics[:equity_start].nil? || metrics[:equity_start].zero?

    ((metrics[:total_pnl] / metrics[:equity_start]) * 100).round(2)
  end

  def build_benchmark_comparison(metrics)
    portfolio_return = metrics[:annualized_return] || 0.0

    # Calculate SPY annualized return from daily returns
    spy_daily_returns = metrics[:spy_returns] || []
    spy_return = if spy_daily_returns.any?
                   geometric_mean = (spy_daily_returns.map do |r|
                     1 + r
                   end.reduce(:*)**(1.0 / spy_daily_returns.length)) - 1
                   (((1 + geometric_mean)**PerformanceCalculator::TRADING_DAYS_PER_YEAR) - 1).round(4)
                 else
                   0.0
                 end

    alpha = metrics[:comparator].calculate_alpha(portfolio_return, spy_return)
    beta = metrics[:comparator].calculate_beta(metrics[:daily_returns] || [], spy_daily_returns)

    {
      spy_return_pct: (spy_return * 100).round(2),
      portfolio_alpha_pct: (alpha * 100).round(2),
      portfolio_beta: beta,
      status: if alpha&.positive?
                "Outperforming SPY by #{(alpha * 100).abs.round(1)}%"
              else
                "Underperforming SPY by #{(alpha * 100).abs.round(1)}%"
              end
    }
  end

  def save_report_to_file(report)
    FileUtils.mkdir_p('tmp/performance_reports')
    filename = "tmp/performance_reports/#{@end_date}.json"

    File.write(filename, JSON.pretty_generate(report))
    filename
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize
