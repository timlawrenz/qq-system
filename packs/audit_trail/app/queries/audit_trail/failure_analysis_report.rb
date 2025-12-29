# frozen_string_literal: true

module AuditTrail
  class FailureAnalysisReport
    # @param start_date [Date, String] Start date for analysis
    # @param end_date [Date, String] End date for analysis (defaults to today)
    # @param strategy_name [String, nil] Optional strategy filter
    def self.generate(start_date: 7.days.ago.to_date, end_date: Date.current, strategy_name: nil)
      new(start_date: start_date, end_date: end_date, strategy_name: strategy_name).generate
    end

    def initialize(start_date:, end_date:, strategy_name: nil)
      @start_date = start_date.to_date
      @end_date = end_date.to_date
      @strategy_name = strategy_name
    end

    def generate
      {
        period: [@start_date, @end_date],
        strategy: @strategy_name || 'All Strategies',
        total_decisions: total_decisions,
        failed_decisions: failed_decisions_count,
        failure_rate: failure_rate,
        failures_by_reason: failures_by_reason,
        failures_by_symbol: failures_by_symbol,
        failures_by_day: failures_by_day,
        top_error_messages: top_error_messages
      }
    end

    private

    def base_scope
      scope = TradeDecision.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
      scope = scope.for_strategy(@strategy_name) if @strategy_name
      scope
    end

    def total_decisions
      base_scope.count
    end

    def failed_decisions_count
      base_scope.failed_decisions.count
    end

    def failure_rate
      total = total_decisions
      return 0.0 if total.zero?
      
      (failed_decisions_count.to_f / total * 100).round(2)
    end

    def failures_by_reason
      # Group by error message patterns
      failed_executions = TradeExecution
        .joins(:trade_decision)
        .where(trade_decisions: { id: base_scope.failed_decisions.select(:id) })
        .where.not(error_message: nil)

      # Categorize common errors
      categories = {
        'Insufficient Buying Power' => 0,
        'API Rate Limit' => 0,
        'Market Closed' => 0,
        'Invalid Symbol' => 0,
        'Order Rejected' => 0,
        'Other' => 0
      }

      failed_executions.each do |execution|
        error = execution.error_message.to_s.downcase
        
        case error
        when /insufficient.*buying.*power/, /not enough.*buying.*power/
          categories['Insufficient Buying Power'] += 1
        when /rate limit/, /too many requests/
          categories['API Rate Limit'] += 1
        when /market.*closed/, /after.*hours/
          categories['Market Closed'] += 1
        when /invalid.*symbol/, /unknown.*symbol/
          categories['Invalid Symbol'] += 1
        when /rejected/, /order.*rejected/
          categories['Order Rejected'] += 1
        else
          categories['Other'] += 1
        end
      end

      categories.reject { |_k, v| v.zero? }
    end

    def failures_by_symbol
      base_scope.failed_decisions
                .group(:symbol)
                .count
                .sort_by { |_symbol, count| -count }
                .to_h
    end

    def failures_by_day
      base_scope.failed_decisions
                .group("DATE(created_at)")
                .count
                .transform_keys { |date_str| Date.parse(date_str.to_s) }
    end

    def top_error_messages
      TradeExecution
        .joins(:trade_decision)
        .where(trade_decisions: { id: base_scope.failed_decisions.select(:id) })
        .where.not(error_message: nil)
        .group(:error_message)
        .count
        .sort_by { |_msg, count| -count }
        .first(10)
        .to_h
    end
  end
end
