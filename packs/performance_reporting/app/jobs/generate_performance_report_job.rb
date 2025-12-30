# frozen_string_literal: true

class GeneratePerformanceReportJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # If strategy_name is nil, generate reports for all Algorithms (fallback to a single default label).
  def perform(strategy_name: nil, snapshot_type: 'weekly')
    strategy_names_for(strategy_name).each do |name|
      generate_report_for(name, snapshot_type)
    end
  rescue StandardError => e
    Rails.logger.error("Performance report job failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise e
  end

  private

  def strategy_names_for(strategy_name)
    return [strategy_name] if strategy_name.present?

    Algorithm.order(:name).pluck(:name).presence || ['Enhanced Congressional']
  end

  def generate_report_for(strategy_name, snapshot_type)
    Rails.logger.info("Starting performance report generation for #{strategy_name} (#{snapshot_type})")

    result = GeneratePerformanceReport.call(
      strategy_name: strategy_name,
      end_date: Date.current
    )

    if result.success?
      Rails.logger.info("Performance report generated successfully: #{result.file_path}")
      Rails.logger.info(
        "Report summary: Total P&L #{result.report_hash.dig(:strategy, :total_pnl)}, " \
        "Sharpe #{result.report_hash.dig(:strategy, :sharpe_ratio)}"
      )
      return
    end

    Rails.logger.error("Performance report generation failed: #{result.errors}")
    raise StandardError, "Report generation failed: #{result.errors}"
  end
end
