# frozen_string_literal: true

# rubocop:disable Lint/UnusedMethodArgument, Layout/LineLength

class GeneratePerformanceReportJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(strategy_name: 'Enhanced Congressional', snapshot_type: 'weekly')
    Rails.logger.info("Starting performance report generation for #{strategy_name}")

    result = GeneratePerformanceReport.call(
      strategy_name: strategy_name,
      end_date: Date.current
    )

    if result.success?
      Rails.logger.info("Performance report generated successfully: #{result.file_path}")
      Rails.logger.info("Report summary: Total P&L #{result.report_hash.dig(:strategy,
                                                                            :total_pnl)}, Sharpe #{result.report_hash.dig(
                                                                              :strategy, :sharpe_ratio
                                                                            )}")
    else
      Rails.logger.error("Performance report generation failed: #{result.errors}")
      raise StandardError, "Report generation failed: #{result.errors}"
    end
  rescue StandardError => e
    Rails.logger.error("Performance report job failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise e
  end
end
# rubocop:enable Lint/UnusedMethodArgument, Layout/LineLength
