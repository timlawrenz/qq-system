# frozen_string_literal: true

module AuditTrail
  # CreateTradeDecision Command
  #
  # Implements the outbox pattern for trade decisions. Captures intent
  # and rationale before execution.
  #
  # Responsibilities:
  # 1. Create a TradeDecision record with "pending" status.
  # 2. Automatically link data lineage (recent ingestion runs).
  # 3. Generate a unique decision_id (UUID).
  class CreateTradeDecision < GLCommand::Callable
    requires :strategy_name, :symbol, :side, :quantity
    allows :strategy_version, :order_type, :limit_price, :primary_quiver_trade_id, :rationale
    returns :trade_decision

    def call
      decision = build_decision
      link_data_lineage(decision)

      decision.save!

      context.trade_decision = decision
      Rails.logger.info("✅ TradeDecision created: #{decision.decision_id} (#{decision.symbol} #{decision.side} #{decision.quantity})")
    end

    private

    def build_decision
      TradeDecision.new(
        decision_id: SecureRandom.uuid,
        strategy_name: context.strategy_name,
        strategy_version: context.strategy_version || '1.0.0',
        symbol: context.symbol.upcase,
        side: context.side.downcase,
        quantity: context.quantity,
        order_type: context.order_type || 'market',
        limit_price: context.limit_price,
        primary_quiver_trade_id: context.primary_quiver_trade_id,
        decision_rationale: context.rationale || {},
        status: 'pending'
      )
    end

    def link_data_lineage(decision)
      # Find recent ingestion runs that might have provided data
      recent_runs = DataIngestionRun
                    .successful
                    .where(completed_at: 24.hours.ago..)
                    .order(completed_at: :desc)
                    .limit(5)

      # Enhance rationale with data lineage
      decision.decision_rationale['data_lineage'] = {
        ingestion_runs: recent_runs.map do |run|
          {
            run_id: run.run_id,
            task_name: run.task_name,
            data_source: run.data_source,
            completed_at: run.completed_at&.iso8601,
            records_fetched: run.records_fetched
          }
        end
      }

      # Set primary_ingestion_run_id if not already set
      decision.primary_ingestion_run_id ||= recent_runs.first&.id
    end
  end
end
