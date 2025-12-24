# frozen_string_literal: true

module AuditTrail
  class SymbolActivityReport
    # @param symbol [String] e.g., "AAPL"
    # @param start_date [Date, String]
    # @param end_date [Date, String]
    def self.generate(symbol:, start_date:, end_date: Date.current)
      new(symbol: symbol, start_date: start_date, end_date: end_date).generate
    end

    def initialize(symbol:, start_date:, end_date:)
      @symbol = symbol.upcase
      @start_date = start_date.to_date
      @end_date = end_date.to_date
    end

    def generate
      {
        symbol: @symbol,
        period: [@start_date, @end_date],
        data_ingested: data_ingested,
        decisions_made: decisions_made,
        trades_executed: trades_executed,
        summary: summary
      }
    end

    private

    def data_ingested
      QuiverTrade
        .for_ticker(@symbol)
        .where(transaction_date: @start_date..@end_date)
        .order(transaction_date: :desc)
        .map do |trade|
          {
            id: trade.id,
            date: trade.transaction_date,
            trader: trade.trader_name,
            type: trade.transaction_type,
            size: trade.trade_size_usd,
            ingested_at: trade.created_at
          }
        end
    end

    def decisions_made
      TradeDecision
        .for_symbol(@symbol)
        .where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
        .order(created_at: :desc)
        .map do |decision|
          {
            decision_id: decision.decision_id,
            strategy: decision.strategy_name,
            side: decision.side,
            quantity: decision.quantity,
            status: decision.status,
            rationale: decision.decision_rationale,
            created_at: decision.created_at
          }
        end
    end

    def trades_executed
      TradeExecution
        .joins(:trade_decision)
        .where(trade_decisions: { symbol: @symbol })
        .where(trade_executions: { created_at: @start_date.beginning_of_day..@end_date.end_of_day })
        .order('trade_executions.created_at DESC')
        .map do |execution|
          {
            execution_id: execution.execution_id,
            status: execution.status,
            filled_qty: execution.filled_quantity,
            filled_price: execution.filled_avg_price,
            alpaca_id: execution.alpaca_order_id,
            error: execution.error_message,
            executed_at: execution.created_at
          }
        end
    end

    def summary
      decisions = TradeDecision.for_symbol(@symbol)
                               .where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
      
      total = decisions.count
      executed = decisions.where(status: 'executed').count
      failed = decisions.where(status: 'failed').count
      
      {
        total_decisions: total,
        executed_count: executed,
        failed_count: failed,
        success_rate: total.positive? ? (executed.to_f / total * 100).round(2) : 0.0
      }
    end
  end
end
