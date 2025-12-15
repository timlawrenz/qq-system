# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

module Workflows
  # ExecuteDailyTrading Chain
  #
  # Orchestrates the complete daily trading workflow:
  # 1. Fetches trading data (congressional + insider)
  # 2. Scores politicians based on performance
  # 3. Gets account equity from Alpaca
  # 4. Generates blended portfolio from multiple strategies
  # 5. Rebalances positions to match target
  # 6. Logs results and metrics
  #
  # This replaces the daily_trading.sh shell script with a testable,
  # composable command chain.
  #
  # Usage:
  #   # Paper trading (default)
  #   result = Workflows::ExecuteDailyTrading.call(trading_mode: 'paper')
  #
  #   # Skip data fetch (use existing data)
  #   result = Workflows::ExecuteDailyTrading.call(
  #     trading_mode: 'paper',
  #     skip_data_fetch: true
  #   )
  #
  #   # Live trading (requires confirmation)
  #   ENV['CONFIRM_LIVE_TRADING'] = 'yes'
  #   result = Workflows::ExecuteDailyTrading.call(trading_mode: 'live')
  class ExecuteDailyTrading < GLCommand::Chainable
    allows :trading_mode, :skip_data_fetch, :skip_politician_scoring, :plan_only

    returns :trading_mode, :account_equity, :target_positions,
            :orders_placed, :final_positions, :metadata

    chain FetchTradingData,
          ScorePoliticians

    def call
      # Set defaults
      context.trading_mode ||= Rails.env.production? ? 'live' : 'paper'
      context.skip_data_fetch ||= false
      context.skip_politician_scoring ||= false
      context.plan_only ||= false

      # Validate live trading
      validate_live_trading! if context.trading_mode == 'live'

      log_start

      # Step 1-2: Fetch data and score politicians (via chain)
      if context.skip_data_fetch
        Rails.logger.info('Skipping data fetch and politician scoring')
        skip_chain
      else
        chain(
          skip_congressional: false,
          skip_insider: false,
          force_rescore: context.skip_politician_scoring ? false : nil
        )
      end

      # Step 3: Get account equity
      load_account_equity

      # Step 4: Analyze signals
      analyze_signals

      # Step 5: Generate target portfolio
      generate_target_portfolio

      # Step 6: Execute rebalancing
      execute_rebalancing

      # Step 7: Verify final state
      verify_positions

      log_completion
    rescue StandardError => e
      log_error(e)
      raise e
    end

    private

    def validate_live_trading!
      unless ENV['CONFIRM_LIVE_TRADING'] == 'yes'
        stop_and_fail!(
          'Live trading requires CONFIRM_LIVE_TRADING=yes environment variable. ' \
          'This prevents accidental live trades.'
        )
      end

      Rails.logger.warn('LIVE TRADING MODE - REAL MONEY AT RISK')
    end

    def log_start
      Rails.logger.info('=' * 64)
      Rails.logger.info('QuiverQuant Daily Trading Process')
      Rails.logger.info("Mode: #{context.trading_mode.upcase}")
      Rails.logger.info('WARNING: LIVE TRADING - REAL MONEY') if context.trading_mode == 'live'
      Rails.logger.info("Started at: #{Time.current}")
      Rails.logger.info('=' * 64)
    end

    def load_account_equity
      Rails.logger.info("Step 3: Loading account data for #{context.trading_mode} mode")

      service = AlpacaService.new
      equity = service.account_equity.to_f

      stop_and_fail!('Failed to load account equity from Alpaca') if equity.nil? || equity <= 0

      context.account_equity = BigDecimal(equity.to_s)

      Rails.logger.info("Account equity: $#{equity.round(2)}")
    rescue StandardError => e
      Rails.logger.error("Failed to load account equity: #{e.message}")
      stop_and_fail!(e)
    end

    def analyze_signals
      Rails.logger.info('Step 4: Analyzing current signals')

      congress_count = QuiverTrade.where(transaction_type: 'Purchase', trader_source: 'congress')
                                  .where(transaction_date: 45.days.ago..)
                                  .distinct
                                  .count(:ticker)

      insider_count = QuiverTrade.where(transaction_type: 'Purchase', trader_source: 'insider')
                                 .where(transaction_date: 30.days.ago..)
                                 .distinct
                                 .count(:ticker)

      total_count = QuiverTrade.count

      Rails.logger.info("Total trades in database: #{total_count}")
      Rails.logger.info("Congressional purchase signals (45d): #{congress_count} tickers")
      Rails.logger.info("Insider purchase signals (30d): #{insider_count} tickers")
    end

    def generate_target_portfolio
      Rails.logger.info('Step 5: Generating target portfolio (Blended Multi-Strategy)')

      result = TradingStrategies::GenerateBlendedPortfolio.call!(
        trading_mode: context.trading_mode,
        total_equity: context.account_equity
      )

      context.target_positions = result.target_positions
      context.metadata = result.metadata

      log_portfolio_summary(result)
    rescue StandardError => e
      Rails.logger.error("Failed to generate portfolio: #{e.message}")
      stop_and_fail!(e)
    end

    def log_portfolio_summary(result)
      positions = result.target_positions
      metadata = result.metadata
      strategy_results = result.strategy_results

      Rails.logger.info("Target portfolio: #{positions.size} positions")

      if metadata
        Rails.logger.info("  Strategy contributions: #{metadata[:strategy_contributions].inspect}")
        Rails.logger.info(
          "  Exposure: Gross #{(metadata[:gross_exposure_pct] * 100).round(1)}%, " \
          "Net #{(metadata[:net_exposure_pct] * 100).round(1)}%"
        )
        Rails.logger.info("  Merge strategy: #{metadata[:merge_strategy]}")

        if metadata[:positions_capped].any?
          Rails.logger.warn("  WARNING: Capped positions: #{metadata[:positions_capped].join(', ')}")
        end
      end

      if strategy_results
        Rails.logger.info('')
        Rails.logger.info('  Strategy execution:')
        strategy_results.each do |strategy, result_data|
          # Support both legacy and new strategy result formats
          status_flag = if result_data.key?(:success)
                          result_data[:success]
                        else
                          result_data[:status].to_s.downcase == 'success'
                        end
          status = status_flag ? 'SUCCESS' : 'FAILED'

          weight = result_data[:weight]
          weight_pct = weight ? (weight * 100).round(0) : nil

          # Count final positions from this strategy based on details.sources metadata
          post_merge_count = positions.count do |p|
            sources = p.details&.dig(:sources) || []
            sources.include?(strategy.to_s) || sources.include?(strategy)
          end

          pre_merge_count =
            if result_data[:positions].respond_to?(:size)
              result_data[:positions].size
            else
              post_merge_count
            end

          base_message = if pre_merge_count == post_merge_count
                           "    #{status} #{strategy}: #{post_merge_count} positions"
                         else
                           "    #{status} #{strategy}: #{post_merge_count} positions in portfolio (#{pre_merge_count} generated)"
                         end

          if weight_pct
            Rails.logger.info("#{base_message} (#{weight_pct}% allocation)")
          else
            Rails.logger.info(base_message)
          end
        end
      end

      if positions.empty?
        Rails.logger.info('')
        Rails.logger.info('No positions in target (signal starvation)')

        if context.trading_mode == 'live'
          Rails.logger.info('LIVE mode: will NOT liquidate existing positions (skipping rebalancing)')
        else
          Rails.logger.info('Will liquidate any existing positions to move to 100% cash')
        end

        return
      end

      # Show top positions
      Rails.logger.info('')
      Rails.logger.info('  Top positions:')
      positions.sort_by { |p| -p.target_value.abs }.first(5).each do |pos|
        side = pos.target_value.positive? ? 'LONG' : 'SHORT'
        details = pos.details || {}
        sources = details[:sources] || []
        consensus = details[:consensus_count]

        if consensus && consensus > 1
          Rails.logger.info(
            "    - #{side} #{pos.symbol}: $#{pos.target_value.abs.round(2)} " \
            "(#{consensus} strategies: #{sources.join(', ')})"
          )
        elsif sources.any?
          Rails.logger.info(
            "    - #{side} #{pos.symbol}: $#{pos.target_value.abs.round(2)} (#{sources.first})"
          )
        else
          Rails.logger.info("    - #{side} #{pos.symbol}: $#{pos.target_value.abs.round(2)}")
        end
      end
    end

    def execute_rebalancing
      if context.target_positions.blank? && context.trading_mode == 'live'
        Rails.logger.info('Skipping rebalancing in LIVE mode because target portfolio is empty (signal starvation)')
        context.orders_placed = []
        return
      end

      result = Trades::RebalanceToTarget.call!(
        target: context.target_positions,
        dry_run: context.plan_only
      )

      context.orders_placed = result.orders_placed

      executed_orders = result.orders_placed.reject { |o| o[:status] == 'skipped' }
      skipped_orders = result.orders_placed.select { |o| o[:status] == 'skipped' }

      skipped_msg = skipped_orders.any? ? ", skipped #{skipped_orders.size}" : ''
      verb = context.plan_only ? 'Planned' : 'Executed'
      Rails.logger.info("#{verb} #{executed_orders.size} orders#{skipped_msg}")

      # Log order details
      if executed_orders.any?
        Rails.logger.info('')
        header = context.plan_only ? 'Planned orders:' : 'Orders executed:'
        Rails.logger.info(header)
        executed_orders.each do |order|
          Rails.logger.info("  - #{order[:side]&.upcase} #{order[:symbol]} (#{order[:status]})")
        end
      end

      if skipped_orders.any?
        Rails.logger.info('')
        Rails.logger.info('Skipped orders (insufficient buying power):')
        skipped_orders.each do |order|
          Rails.logger.info("  - #{order[:side]&.upcase} #{order[:symbol]} ($#{order[:attempted_amount]})")
        end
        Rails.logger.info('Tip: Add cash to account for better rebalancing flexibility')
      end
    rescue StandardError => e
      Rails.logger.error("Rebalancing failed: #{e.message}")
      stop_and_fail!(e)
    end

    def verify_positions
      Rails.logger.info('Step 6: Verifying positions')

      service = AlpacaService.new
      positions = service.current_positions
      equity = service.account_equity

      holdings_value = positions.sum { |p| p[:market_value] }
      cash = equity - holdings_value

      context.final_positions = positions

      Rails.logger.info("Account equity: $#{equity.round(2)}")
      Rails.logger.info("Current positions: #{positions.size}")
      Rails.logger.info("Holdings value: $#{holdings_value.round(2)}")
      Rails.logger.info("Cash: $#{cash.round(2)}")

      if positions.any?
        Rails.logger.info('')
        Rails.logger.info('Top positions:')
        positions.sort_by { |p| -p[:market_value] }.first(5).each do |pos|
          pct = (pos[:market_value] / equity * 100).round(2)
          Rails.logger.info("  - #{pos[:symbol]}: $#{pos[:market_value].round(2)} (#{pct}%)")
        end
      end
    rescue StandardError => e
      Rails.logger.error("Failed to verify positions: #{e.message}")
      # Don't fail the whole workflow if verification fails
      Rails.logger.warn('Continuing despite verification error')
    end

    def log_completion
      Rails.logger.info('')
      Rails.logger.info('=' * 64)
      Rails.logger.info('Daily Trading Complete')
      Rails.logger.info("Finished at: #{Time.current}")
      Rails.logger.info('=' * 64)
    end

    def log_error(error)
      Rails.logger.error('')
      Rails.logger.error('=' * 64)
      Rails.logger.error('Daily Trading FAILED')
      Rails.logger.error("Error: #{error.message}")
      Rails.logger.error(error.backtrace.join("\n")) if error.backtrace
      Rails.logger.error("Failed at: #{Time.current}")
      Rails.logger.error('=' * 64)
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
