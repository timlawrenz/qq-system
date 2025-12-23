# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

class GeneratePerformanceReport < GLCommand::Callable
  requires :start_date, :end_date, :strategy_name

  returns :report_hash, :file_path, :snapshot_id

  MAX_SNAPSHOT_DECIMAL_ABS = 999_999.9999

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
    stop_and_fail!(e.message)
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

    equity_end = alpaca_service.account_equity

    # Fetch account equity history
    equity_history = alpaca_service.account_equity_history(
      start_date: @start_date,
      end_date: @end_date
    )

    # Alpaca can return [] for new accounts or API issues; avoid misleading $100k defaults.
    equity_history = [{ timestamp: @end_date, equity: equity_end }] if equity_history.blank?

    # Fetch filled orders in the period (via Alpaca API) so local runs don't depend on DB state
    filled_orders = alpaca_service
                    .orders_history(start_date: @start_date, end_date: @end_date)
                    .select { |o| o.respond_to?(:status) && o.status.to_s == 'filled' }

    period_cash_transfers = alpaca_service.cash_transfers(start_date: @start_date, end_date: @end_date)

    # Lifetime cash in/out (what you actually care about): all contributions vs current equity.
    lifetime_cash_transfers = alpaca_service.cash_transfers(start_date: Date.new(2000, 1, 1), end_date: @end_date)
    lifetime_net_contributions = lifetime_cash_transfers.sum { |t| t[:amount] }

    # Align cashflows to the same window as the equity history we actually have.
    twr_start = equity_history.first&.dig(:timestamp) || @start_date
    cash_transfers_in_window = period_cash_transfers.select { |t| t[:date].between?(twr_start, @end_date) }

    period_net_contributions = cash_transfers_in_window.sum { |t| t[:amount] }
    flows_by_date = cash_transfers_in_window.group_by { |t| t[:date] }
                                            .transform_values { |rows| rows.sum { |r| r[:amount] } }

    # Calculate daily returns
    daily_returns = calculate_daily_returns(equity_history)

    # Prefer Alpaca's deposit-adjusted profit_loss_pct when available.
    # This avoids nonsense TWR when large contributions happen early in the period.
    alpaca_twr = equity_history.last&.dig(:profit_loss_pct)
    if alpaca_twr.present?
      twr_return = alpaca_twr
      twr_method = 'alpaca_profit_loss_pct'
    else
      twr_daily_returns = calculate_time_weighted_daily_returns(equity_history, flows_by_date)
      twr_return = calculate_compound_return(twr_daily_returns)
      twr_method = 'manual_cashflow_adjusted'
    end

    # Calculate core metrics
    equity_start = equity_history.map { |p| p[:equity].to_f }.find(&:positive?)
    equity_start = BigDecimal(equity_start.to_s) if equity_start
    equity_start ||= equity_end
    equity_end = equity_history.last&.dig(:equity) || equity_end
    trading_days = (@end_date - @start_date).to_i.clamp(1, Float::INFINITY)

    total_pnl = equity_end - equity_start

    # Period profit vs period cashflows (uses equity_history's first point as the anchor).
    cashflow_equity_start = equity_history.first&.dig(:equity).to_f
    period_net_profit = equity_end.to_f - cashflow_equity_start - period_net_contributions.to_f
    period_net_profit_pct = if period_net_contributions.to_f.zero?
                              nil
                            else
                              ((period_net_profit / period_net_contributions.to_f) * 100).round(2)
                            end

    # Lifetime profit vs lifetime cashflows (headline: current equity vs all cash you've put in).
    lifetime_net_profit = equity_end.to_f - lifetime_net_contributions.to_f
    lifetime_net_profit_pct = if lifetime_net_contributions.to_f.zero?
                                nil
                              else
                                ((lifetime_net_profit / lifetime_net_contributions.to_f) * 100).round(2)
                              end

    {
      equity_history: equity_history,
      equity_start: equity_start,
      equity_end: equity_end,
      total_pnl: total_pnl,
      daily_returns: daily_returns,
      lifetime_net_contributions: lifetime_net_contributions,
      lifetime_net_profit: lifetime_net_profit,
      lifetime_net_profit_pct: lifetime_net_profit_pct,
      period_net_contributions: period_net_contributions,
      period_net_profit: period_net_profit,
      period_net_profit_pct: period_net_profit_pct,
      cashflow_equity_start: cashflow_equity_start,
      twr_return: twr_return,
      twr_start_date: twr_start,
      twr_method: twr_method,
      sharpe_ratio: calculator.calculate_sharpe_ratio(daily_returns),
      max_drawdown: calculator.calculate_max_drawdown(equity_history.pluck(:equity)),
      volatility: calculator.calculate_volatility(daily_returns),
      win_rate: calculator.calculate_win_rate(filled_orders),
      total_trades: filled_orders.count,
      winning_trades: count_winning_trades(filled_orders),
      losing_trades: count_losing_trades(filled_orders),
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
    trades.count { |t| trade_profitable?(t) == true }
  end

  def count_losing_trades(trades)
    trades.count { |t| trade_profitable?(t) == false }
  end

  # rubocop:disable Style/ReturnNilInPredicateMethodDefinition
  def trade_profitable?(trade)
    # Alpaca order payloads don't include realized P&L; treat profitability as unknown.
    return nil unless trade.respond_to?(:realized_pl) && trade.realized_pl.present?

    trade.realized_pl.positive?
  end
  # rubocop:enable Style/ReturnNilInPredicateMethodDefinition

  def create_snapshot(metrics)
    # Calculate Calmar ratio now that we have both values
    calmar = metrics[:calculator].calculate_calmar_ratio(
      metrics[:annualized_return] || 0.0,
      metrics[:max_drawdown]
    )

    sharpe_ratio = sanitize_snapshot_decimal(metrics[:sharpe_ratio])
    max_drawdown = sanitize_snapshot_decimal(metrics[:max_drawdown])
    volatility = sanitize_snapshot_decimal(metrics[:volatility])
    win_rate = sanitize_snapshot_decimal(metrics[:win_rate])
    calmar = sanitize_snapshot_decimal(calmar)

    # Allow regenerating the report for the same date/strategy without failing uniqueness validations.
    PerformanceSnapshot
      .where(snapshot_date: @end_date, snapshot_type: 'weekly', strategy_name: @strategy_name)
      .delete_all

    PerformanceSnapshot.create!(
      snapshot_date: @end_date,
      snapshot_type: :weekly, # Default to weekly for now
      strategy_name: @strategy_name,
      total_equity: metrics[:equity_end],
      total_pnl: metrics[:total_pnl],
      sharpe_ratio: sharpe_ratio,
      max_drawdown_pct: max_drawdown,
      volatility: volatility,
      win_rate: win_rate,
      total_trades: metrics[:total_trades],
      winning_trades: metrics[:winning_trades],
      losing_trades: metrics[:losing_trades],
      calmar_ratio: calmar,
      metadata: build_metadata(metrics)
    )
  end

  def sanitize_snapshot_decimal(value)
    return nil if value.nil?

    float = value.to_f
    return nil if float.infinite? || float.nan?
    return value if float.abs < MAX_SNAPSHOT_DECIMAL_ABS

    Rails.logger.warn("PerformanceReport: metric overflow (#{float}), storing nil")
    nil
  end

  def build_metadata(metrics)
    {
      period: {
        start_date: @start_date.to_s,
        end_date: @end_date.to_s,
        trading_days: metrics[:daily_returns]&.length || 0
      },
      cashflows: {
        start_date: (metrics[:twr_start_date] || @start_date).to_s,
        end_date: @end_date.to_s,
        method: metrics[:twr_method],
        cashflow_equity_start: metrics[:cashflow_equity_start]&.to_f&.round(2),

        # Period window (aligned to equity_history window)
        period_net_contributions: metrics[:period_net_contributions]&.to_f&.round(2),
        period_net_profit: metrics[:period_net_profit]&.to_f&.round(2),
        period_net_profit_pct: metrics[:period_net_profit_pct]&.to_f,

        # Lifetime (all cash in/out, what you care about)
        lifetime_net_contributions: metrics[:lifetime_net_contributions]&.to_f&.round(2),
        lifetime_net_profit: metrics[:lifetime_net_profit]&.to_f&.round(2),
        lifetime_net_profit_pct: metrics[:lifetime_net_profit_pct]&.to_f,

        twr_return_pct: metrics[:twr_return] ? (metrics[:twr_return].to_f * 100).round(2) : nil
      },
      warnings: build_warnings(metrics)
    }
  end

  def build_warnings(metrics)
    warnings = []

    if metrics[:daily_returns].nil? || metrics[:daily_returns].length < PerformanceCalculator::WARN_DAYS_FOR_SHARPE
      warnings << "Limited data available (#{metrics[:daily_returns]&.length || 0} days)"
    end

    warnings << 'No trades executed in this period' if metrics[:total_trades].zero?

    if metrics[:total_trades].positive? && metrics[:win_rate].nil?
      warnings << 'Trade-level P&L unavailable; win/loss stats omitted'
    end

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
        # Context for interpreting P&L
        equity_start: metrics[:equity_start]&.to_f&.round(2),
        equity_end: metrics[:equity_end]&.to_f&.round(2),
        cashflow_start_date: snapshot.metadata.dig('cashflows', 'start_date'),
        cashflow_end_date: snapshot.metadata.dig('cashflows', 'end_date'),
        twr_method: snapshot.metadata.dig('cashflows', 'method'),

        # Headline: lifetime profit vs all cash in/out
        net_contributions: snapshot.metadata.dig('cashflows', 'lifetime_net_contributions'),
        net_profit: snapshot.metadata.dig('cashflows', 'lifetime_net_profit'),
        net_profit_pct: snapshot.metadata.dig('cashflows', 'lifetime_net_profit_pct'),

        # Diagnostics
        period_net_contributions: snapshot.metadata.dig('cashflows', 'period_net_contributions'),
        period_net_profit: snapshot.metadata.dig('cashflows', 'period_net_profit'),
        period_net_profit_pct: snapshot.metadata.dig('cashflows', 'period_net_profit_pct'),
        twr_return_pct: snapshot.metadata.dig('cashflows', 'twr_return_pct'),
        # Use snapshot values so output matches what was persisted (and benefits from overflow sanitization)
        sharpe_ratio: snapshot.sharpe_ratio&.to_f,
        max_drawdown_pct: snapshot.max_drawdown_pct&.to_f,
        volatility: snapshot.volatility&.to_f,
        win_rate: snapshot.win_rate&.to_f,
        total_trades: metrics[:total_trades],
        winning_trades: win_loss_known?(metrics) ? metrics[:winning_trades] : nil,
        losing_trades: win_loss_known?(metrics) ? metrics[:losing_trades] : nil,
        known_trade_outcomes: metrics[:winning_trades] + metrics[:losing_trades],
        calmar_ratio: snapshot.calmar_ratio&.to_f
      },
      interpretation: build_interpretation(snapshot),
      warnings: snapshot.metadata['warnings']
    }

    # Add SPY benchmark comparison if available
    report[:benchmark] = build_benchmark_comparison(metrics) if metrics[:spy_returns].present?

    report
  end

  def calculate_pnl_percentage(metrics)
    equity_start = metrics[:equity_start]
    total_pnl = metrics[:total_pnl]

    return nil if equity_start.nil? || equity_start.to_f.zero?

    ((total_pnl.to_f / equity_start) * 100).round(2).to_f
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

  def build_interpretation(snapshot)
    twr = snapshot.metadata.dig('cashflows', 'twr_return_pct')
    contrib = snapshot.metadata.dig('cashflows', 'lifetime_net_contributions')
    net_profit = snapshot.metadata.dig('cashflows', 'lifetime_net_profit')

    parts = []
    parts << (contrib.nil? ? 'Net contributions: n/a' : "Net contributions: $#{contrib}")
    parts << (net_profit.nil? ? 'Net profit: n/a' : "Net profit: $#{net_profit}")
    parts << (twr.nil? ? 'TWR: n/a' : "TWR: #{twr}%")
    parts << "Max drawdown: #{snapshot.max_drawdown_pct.to_f.round(2)}%" if snapshot.max_drawdown_pct

    parts.join(' | ')
  end

  def win_loss_known?(metrics)
    metrics[:total_trades].positive? && !metrics[:win_rate].nil?
  end

  def calculate_time_weighted_daily_returns(equity_history, flows_by_date)
    return [] if equity_history.length < 2

    equity_history.each_cons(2).filter_map do |prev, curr|
      prev_equity = prev[:equity].to_f
      curr_equity = curr[:equity].to_f
      next nil if prev_equity.zero?

      flow = (flows_by_date[curr[:timestamp]] || 0).to_f
      (curr_equity - prev_equity - flow) / prev_equity
    end
  end

  def calculate_compound_return(daily_returns)
    return nil if daily_returns.blank?

    daily_returns.reduce(1.0) { |acc, r| acc * (1.0 + r.to_f) } - 1.0
  end

  def save_report_to_file(report)
    FileUtils.mkdir_p('tmp/performance_reports')
    filename = "tmp/performance_reports/#{@end_date}.json"

    File.write(filename, JSON.pretty_generate(report))
    filename
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
