# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingStrategies::RefreshCompanyProfiles do
  describe '.call' do
    before do
      GovernmentContract.delete_all
      CompanyProfile.delete_all
    end

    it 'refreshes profiles for tickers seen in recent government contracts' do
      GovernmentContract.create!(
        contract_id: 'C-1',
        ticker: 'AAPL',
        contract_value: 50_000_000,
        award_date: 2.days.ago.to_date
      )

      profile = CompanyProfile.create!(ticker: 'AAPL', source: 'fmp', fetched_at: 2.months.ago)

      allow(TradingStrategies::FundamentalDataService).to receive(:get_company_profile)
        .with('AAPL') do
          profile.update!(fetched_at: Time.current)
          profile
        end

      result = described_class.call(lookback_days: 30)

      expect(result).to be_success
      expect(result.tickers_seen).to eq(1)
      expect(result.profiles_refreshed).to eq(1)
      expect(result.profiles_failed).to eq(0)
    end
  end
end
