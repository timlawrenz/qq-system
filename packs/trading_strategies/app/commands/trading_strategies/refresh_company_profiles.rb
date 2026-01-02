# frozen_string_literal: true

module TradingStrategies
  # RefreshCompanyProfiles
  #
  # Daily maintenance command to keep cached company profile data (sector/industry/etc.)
  # warm for tickers we are likely to trade.
  class RefreshCompanyProfiles < GLCommand::Callable
    allows :lookback_days, :max_tickers

    returns :tickers_seen, :profiles_refreshed, :profiles_skipped, :profiles_failed

    def call
      context.lookback_days ||= 180
      context.max_tickers ||= 200

      tickers = fetch_recent_contractor_tickers
      context.tickers_seen = tickers.size

      refreshed = 0
      skipped = 0
      failed = 0

      tickers.each do |ticker|
        existing_fetched_at = CompanyProfile.find_by(ticker: ticker)&.fetched_at

        profile = FundamentalDataService.get_company_profile(ticker)

        if profile.nil?
          failed += 1
          next
        end

        if existing_fetched_at.nil? || profile.fetched_at != existing_fetched_at
          refreshed += 1
        else
          skipped += 1
        end
      end

      context.profiles_refreshed = refreshed
      context.profiles_skipped = skipped
      context.profiles_failed = failed

      context
    end

    private

    def fetch_recent_contractor_tickers
      start_date = context.lookback_days.to_i.days.ago.to_date

      tickers = GovernmentContract
        .where(award_date: start_date..Date.current)
        .distinct
        .pluck(:ticker)

      if tickers.blank?
        # Bootstrap cache even before contracts ingestion is running.
        tickers = QuiverTrade
          .where(trader_source: %w[congress insider])
          .purchases
          .recent(30)
          .distinct
          .limit(context.max_tickers)
          .pluck(:ticker)
      end

      tickers
        .compact
        .map { |t| t.to_s.upcase }
        .uniq
        .first(context.max_tickers)
    end
  end
end
