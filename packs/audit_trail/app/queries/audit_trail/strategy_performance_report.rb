# frozen_string_literal: true

module AuditTrail
  class StrategyPerformanceReport
    def self.generate(strategy_name: nil)
      scope = TradeDecision.all
      scope = scope.for_strategy(strategy_name) if strategy_name
      
      results = scope.group(:strategy_name)
                     .select(
                       'strategy_name',
                       'COUNT(*) as total_signals',
                       "COUNT(*) FILTER (WHERE status = 'executed') as executed",
                       "COUNT(*) FILTER (WHERE status = 'failed') as failed",
                       "COUNT(*) FILTER (WHERE status = 'cancelled') as cancelled",
                       'ROUND(100.0 * COUNT(*) FILTER (WHERE status = \'executed\') / COUNT(*), 2) as success_rate'
                     )
                     .order('success_rate DESC')
      
      results.map do |r|
        {
          strategy: r.strategy_name,
          total_signals: r.total_signals,
          executed: r.executed,
          failed: r.failed,
          cancelled: r.cancelled,
          success_rate: r.success_rate.to_f
        }
      end
    end
  end
end
