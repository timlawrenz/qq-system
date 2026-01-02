# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingStrategies::FundamentalDataService do
  before do
    Rails.cache.clear
  end

  describe '.get_company_profile' do
    it 'caches the profile in the database and reuses it' do
      allow(FmpClient).to receive(:new).and_return(
        instance_double(
          FmpClient,
          fetch_company_profile: {
            ticker: 'LMT',
            company_name: 'Lockheed Martin',
            sector: 'Industrials',
            industry: 'Aerospace & Defense',
            cik: '0000936468',
            cusip: '539830109',
            isin: 'US5398301094',
            annual_revenue: nil
          }
        )
      )

      first = described_class.get_company_profile('LMT')
      second = described_class.get_company_profile('LMT')

      expect(first).to be_present
      expect(second).to be_present
      expect(CompanyProfile.count).to eq(1)
      expect(second.id).to eq(first.id)
      expect(second.sector).to eq('Industrials')
    end
  end

  describe '.get_sector/.get_industry' do
    it 'returns sector/industry from cached profile' do
      CompanyProfile.create!(
        ticker: 'AAPL',
        company_name: 'Apple Inc.',
        sector: 'Technology',
        industry: 'Consumer Electronics',
        source: 'fmp',
        fetched_at: Time.current
      )

      expect(described_class.get_sector('AAPL')).to eq('Technology')
      expect(described_class.get_industry('AAPL')).to eq('Consumer Electronics')
    end
  end
end
