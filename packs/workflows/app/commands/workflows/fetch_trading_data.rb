# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize, Metrics/MethodLength

module Workflows
  # FetchTradingData Command
  #
  # Fetches recent trading data from QuiverQuant API:
  # - Congressional trades (last 7 days)
  # - Insider trades (last 7 days)
  #
  # This command handles API rate limits, deduplication, and error recovery.
  class FetchTradingData < GLCommand::Callable
    allows :skip_congressional, :skip_insider, :lookback_days, :record_operations, :api_calls

    returns :congressional_count, :congressional_new_count,
            :insider_count, :insider_new_count, :api_calls

    def call
      context.lookback_days ||= 7

      # Skip if explicitly requested (for testing or when data already loaded)
      if context.skip_congressional && context.skip_insider
        Rails.logger.info('FetchTradingData: Skipping all data fetch')
        set_zero_counts
        return
      end

      AuditTrail::LogDataIngestion.call(
        task_name: self.class.name,
        data_source: 'quiverquant_combined'
      ) do |_run|
        fetch_congressional_trades unless context.skip_congressional
        fetch_insider_trades unless context.skip_insider

        # Return combined result for logging
        {
          fetched: (context.congressional_count || 0) + (context.insider_count || 0),
          created: (context.congressional_new_count || 0) + (context.insider_new_count || 0),
          updated: 0, # Not explicitly tracked here
          record_operations: context.record_operations || [],
          api_calls: context.api_calls || []
        }
      end
    end

    private

    def set_zero_counts
      context.congressional_count = 0
      context.congressional_new_count = 0
      context.insider_count = 0
      context.insider_new_count = 0
      context.record_operations = []
      context.api_calls = []
    end

    def fetch_congressional_trades
      Rails.logger.info('FetchTradingData: Fetching congressional trades')

      client = QuiverClient.new
      start_date = context.lookback_days.days.ago.to_date
      end_date = Date.current

      trades = client.fetch_congressional_trades(
        start_date: start_date,
        end_date: end_date,
        limit: 1000
      )

      context.record_operations ||= []
      context.api_calls ||= []
      context.api_calls += client.api_calls if client.api_calls

      new_count = 0
      trades.each do |trade_data|
        # Skip malformed records with missing trade date
        next if trade_data[:transaction_date].nil?

        qt = QuiverTrade.find_or_create_by!(
          ticker: trade_data[:ticker],
          transaction_date: trade_data[:transaction_date],
          trader_name: trade_data[:trader_name],
          transaction_type: trade_data[:transaction_type]
        ) do |t|
          t.company = trade_data[:company]
          t.trader_source = 'congress'
          t.trade_size_usd = trade_data[:trade_size_usd]
          t.disclosed_at = trade_data[:disclosed_at]
        end

        if qt.previously_new_record?
          new_count += 1
          context.record_operations << { record: qt, operation: 'created' }
        else
          context.record_operations << { record: qt, operation: 'skipped' }
        end
      end

      context.congressional_count = trades.size
      context.congressional_new_count = new_count

      Rails.logger.info(
        "FetchTradingData: Congressional - #{trades.size} trades, #{new_count} new (no local date filter)"
      )
    rescue StandardError => e
      Rails.logger.error("FetchTradingData: Failed to fetch congressional trades: #{e.message}")
      stop_and_fail!(e)
    end

    def fetch_insider_trades
      Rails.logger.info('FetchTradingData: Fetching insider trades')

      # Check if insider strategy is enabled
      unless insider_strategy_enabled?
        Rails.logger.info('FetchTradingData: Insider strategy disabled, skipping fetch')
        context.insider_count = 0
        context.insider_new_count = 0
        return
      end

      start_date = context.lookback_days.days.ago.to_date
      end_date = Date.current

      result = FetchInsiderTrades.call(
        start_date: start_date,
        end_date: end_date,
        limit: 1000
      )

      if result.success?
        context.insider_count = result.total_count
        context.insider_new_count = result.new_count
        context.record_operations ||= []
        context.record_operations += result.record_operations if result.record_operations
        context.api_calls ||= []
        context.api_calls += result.api_calls if result.api_calls

        Rails.logger.info(
          "FetchTradingData: Insider - #{result.total_count} trades, #{result.new_count} new, " \
          "#{result.updated_count} updated, #{result.error_count} errors"
        )
      else
        Rails.logger.error("FetchTradingData: FetchInsiderTrades failed: #{result.full_error_message}")
        stop_and_fail!(result.full_error_message)
      end
    rescue StandardError => e
      Rails.logger.error("FetchTradingData: Failed to fetch insider trades: #{e.message}")
      stop_and_fail!(e)
    end

    def insider_strategy_enabled?
      config_path = Rails.root.join('config/portfolio_strategies.yml')
      return false unless File.exist?(config_path)

      configs = YAML.load_file(config_path)

      # Check paper/live/current environments
      [Rails.env, 'paper', 'live'].any? do |env|
        configs.dig(env, 'strategies', 'insider', 'enabled')
      end
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
