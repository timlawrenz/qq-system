# frozen_string_literal: true

require 'faraday'

module SenateEfd
  # Top-level orchestrator for the Senate EFD extraction pipeline.
  #
  # Composes SessionManager, IndexFetcher, and ReportParser into a single
  # workflow that fetches all Senator stock trades disclosed since a watermark
  # date.  Returns data in the same format as the (now-defunct) community
  # S3 aggregator so no downstream code changes are needed.
  #
  # Design goals (per user direction):
  #   - Availability > speed — we poll at most once daily.
  #   - Random jitter between requests to avoid pattern-based rate limiting.
  #   - Watermark-based delta fetching to minimise load on the Senate servers.
  #
  # Usage
  #   client = SenateEfd::Client.new
  #   trades = client.fetch_trades_since(45.days.ago.to_date)
  #   # => [{ ticker:, company:, trader_name:, trader_source: 'congress',
  #   #       transaction_date:, transaction_type:, trade_size_usd:,
  #   #       disclosed_at: }, …]
  #
  class Client
    # Jitter range (seconds) between individual report fetches.
    # Between 1.5 and 4.0 seconds — conservative for once-daily polling.
    REPORT_JITTER_MIN = 1.5
    REPORT_JITTER_MAX = 4.0

    attr_reader :api_calls

    def initialize
      @session = SessionManager.new
      @api_calls = []
    end

    # Fetch all Senate stock trades disclosed on or after `watermark_date`.
    #
    # @param watermark_date [Date, nil]  only return trades disclosed on/after
    #   this date.  Pass nil to fetch everything (use sparingly).
    # @param max_reports [Integer]  safety cap on number of individual PTR pages
    #   to crawl.  Default 100 — covers ~2 months of daily filings.
    # @return [Array<Hash>] normalized trade hashes matching the former
    #   HouseSenateDisclosuresClient senate format:
    #   :ticker, :company, :trader_name, :trader_source, :transaction_date,
    #   :transaction_type, :trade_size_usd, :disclosed_at
    def fetch_trades_since(watermark_date, max_reports: 100)
      Rails.logger.info(
        "[SenateEfd::Client] Fetching Senate trades since #{watermark_date || 'beginning'}"
      )

      # Phase 1: Authenticate
      @session.ensure_authenticated

      # Phase 2: Get PTR index
      indexer = IndexFetcher.new(@session)
      reports = indexer.fetch_ptrs_since(watermark_date)
      @api_calls.concat(indexer.api_calls)

      if reports.empty?
        Rails.logger.info('[SenateEfd::Client] No new PTRs to process')
        return []
      end

      # Phase 3: Parse each PTR
      trades = parse_reports(reports, max_reports)

      Rails.logger.info(
        "[SenateEfd::Client] Complete: #{trades.size} trades extracted " \
        "from #{[reports.size, max_reports].min} PTRs"
      )

      trades
    rescue StandardError => e
      Rails.logger.error("[SenateEfd::Client] Fatal error: #{e.message}")
      []
    end

    private

    def parse_reports(reports, max_reports)
      limit = [reports.size, max_reports].min
      parser = ReportParser.new(@session)
      trades = []

      Rails.logger.info(
        "[SenateEfd::Client] Processing #{limit} of #{reports.size} PTRs"
      )

      reports.first(max_reports).each_with_index do |report, idx|
        begin
          report_trades = parser.parse_report(report[:url], report)
          trades.concat(report_trades)
          log_progress(idx + 1, limit, trades.size)
        rescue StandardError => e
          Rails.logger.warn(
            "[SenateEfd::Client] Skipped PTR #{report[:url]} — #{e.message}"
          )
        end

        report_jitter_sleep unless idx == reports.size - 1
      end

      @api_calls.concat(parser.api_calls)
      trades
    end

    def log_progress(current, total, trade_count)
      return unless (current % 10).zero?

      Rails.logger.info(
        "[SenateEfd::Client] Progress: #{current}/#{total} " \
        "PTRs — #{trade_count} trades so far"
      )
    end

    def report_jitter_sleep
      seconds = REPORT_JITTER_MIN + (rand * (REPORT_JITTER_MAX - REPORT_JITTER_MIN))
      sleep(seconds)
    end
  end
end
