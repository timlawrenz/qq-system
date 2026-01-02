# frozen_string_literal: true

module TradingStrategies
  # FundamentalDataService
  #
  # Read-through cache for company profile/fundamentals needed by strategies.
  # Primary source: Financial Modeling Prep (FMP) via CompanyProfile records.
  class FundamentalDataService
    CACHE_TTL = 30.days
    DAILY_CALL_CEILING = 200

    # USD annual revenue (approximate fallback for materiality filtering only)
    HARDCODED_ANNUAL_REVENUE_USD = {
      'LMT' => 67_000_000_000,
      'NOC' => 41_000_000_000,
      'RTX' => 69_000_000_000,
      'BA' => 77_000_000_000,
      'GD' => 42_000_000_000,
      'HII' => 11_000_000_000
    }.freeze

    class << self
      def get_company_profile(ticker, force_refresh: false)
        return nil if ticker.blank?

        sym = ticker.to_s.upcase
        record = CompanyProfile.find_by(ticker: sym)

        fresh_enough = record.present? && record.fetched_at >= CACHE_TTL.ago
        return record if fresh_enough && !force_refresh

        return record unless allowed_to_call_fmp?

        payload = FmpClient.new.fetch_company_profile(sym)
        return record if payload.nil?

        attrs = {
          ticker: sym,
          company_name: payload[:company_name],
          sector: payload[:sector],
          industry: payload[:industry],
          cik: payload[:cik],
          cusip: payload[:cusip],
          isin: payload[:isin],
          annual_revenue: payload[:annual_revenue].presence,
          source: 'fmp',
          fetched_at: Time.current
        }

        record ||= CompanyProfile.new(ticker: sym)
        record.assign_attributes(attrs)
        record.save!

        increment_daily_calls!

        record
      rescue StandardError => e
        Rails.logger.warn("[FundamentalDataService] FMP profile fetch failed for #{sym}: #{e.message}")
        record
      end

      def get_sector(ticker)
        get_company_profile(ticker)&.sector
      end

      def get_industry(ticker)
        get_company_profile(ticker)&.industry
      end

      # @return [BigDecimal, nil]
      def get_annual_revenue(ticker)
        return nil if ticker.blank?

        sym = ticker.to_s.upcase

        profile_revenue = get_company_profile(sym)&.annual_revenue
        return BigDecimal(profile_revenue.to_s) if profile_revenue.present?

        revenue = HARDCODED_ANNUAL_REVENUE_USD[sym]
        revenue.nil? ? nil : BigDecimal(revenue.to_s)
      end

      private

      def allowed_to_call_fmp?
        return false if daily_calls_today >= DAILY_CALL_CEILING

        true
      end

      def daily_calls_today
        Rails.cache.fetch(daily_calls_cache_key, expires_in: 2.days) { 0 }.to_i
      end

      def increment_daily_calls!
        Rails.cache.write(daily_calls_cache_key, daily_calls_today + 1, expires_in: 2.days)
      end

      def daily_calls_cache_key
        "fmp:daily_calls:#{Date.current}"
      end
    end
  end
end
