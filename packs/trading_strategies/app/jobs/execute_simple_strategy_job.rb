# frozen_string_literal: true

# ExecuteSimpleStrategyJob
#
# Background job that orchestrates the simple trading strategy execution.
# This job runs on a daily schedule and coordinates between strategy generation
# and trade execution.
#
# The job performs the following steps:
# 1. Calls TradingStrategies::GenerateTargetPortfolio to get the target portfolio
# 2. Calls Trades::RebalanceToTarget with the generated target portfolio to execute trades
class ExecuteSimpleStrategyJob < ApplicationJob
  def perform
    # Generate target portfolio using the Simple strategy
    target_portfolio_result = TradingStrategies::GenerateTargetPortfolio.call

    # If target portfolio generation failed, log and stop
    unless target_portfolio_result.success?
      Rails.logger.error("ExecuteSimpleStrategyJob: GenerateTargetPortfolio failed: #{target_portfolio_result.error}")
      return
    end

    # Execute trades to rebalance to the target portfolio
    rebalance_result = Trades::RebalanceToTarget.call(target: target_portfolio_result.target_positions)

    # Log the results
    if rebalance_result.success?
      orders_count = rebalance_result.orders_placed.size
      Rails.logger.info(
        "ExecuteSimpleStrategyJob: Successfully executed simple strategy with #{orders_count} orders placed"
      )
    else
      Rails.logger.error("ExecuteSimpleStrategyJob: RebalanceToTarget failed: #{rebalance_result.error}")
    end
  rescue StandardError => e
    Rails.logger.error("ExecuteSimpleStrategyJob: Unexpected error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise
  end
end
