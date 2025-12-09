# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PoliticianProfile, type: :model do
  describe 'associations' do
    it 'has many committee_memberships' do
      expect(subject).to respond_to(:committee_memberships)
    end

    it 'has many committees through committee_memberships' do
      expect(subject).to respond_to(:committees)
    end
  end

  describe 'validations' do
    it 'validates presence of name' do
      politician = build(:politician_profile, name: nil)
      expect(politician).not_to be_valid
      expect(politician.errors[:name]).to include("can't be blank")
    end

    it 'validates uniqueness of bioguide_id when present' do
      create(:politician_profile, bioguide_id: 'P000197')
      politician = build(:politician_profile, bioguide_id: 'P000197')
      expect(politician).not_to be_valid
      expect(politician.errors[:bioguide_id]).to include('has already been taken')
    end

    it 'allows nil bioguide_id' do
      politician = build(:politician_profile, bioguide_id: nil)
      expect(politician).to be_valid
    end

    it 'validates quality_score is between 0 and 10' do
      politician = build(:politician_profile, quality_score: 15.0)
      expect(politician).not_to be_valid

      politician.quality_score = -1.0
      expect(politician).not_to be_valid

      politician.quality_score = 5.0
      expect(politician).to be_valid
    end

    it 'validates total_trades is non-negative' do
      politician = build(:politician_profile, total_trades: -1)
      expect(politician).not_to be_valid

      politician.total_trades = 0
      expect(politician).to be_valid
    end

    it 'validates winning_trades is non-negative' do
      politician = build(:politician_profile, winning_trades: -1)
      expect(politician).not_to be_valid

      politician.winning_trades = 0
      expect(politician).to be_valid
    end

    it 'validates average_return is numeric' do
      politician = build(:politician_profile, average_return: 'not a number')
      expect(politician).not_to be_valid

      politician.average_return = 5.5
      expect(politician).to be_valid
    end
  end

  describe 'scopes' do
    let!(:politician_with_score) { create(:politician_profile, quality_score: 8.5) }
    let!(:politician_without_score) { create(:politician_profile, quality_score: nil) }
    let!(:low_quality) { create(:politician_profile, quality_score: 3.0) }
    let!(:high_quality) { create(:politician_profile, quality_score: 9.0) }
    let!(:recently_scored) { create(:politician_profile, last_scored_at: 1.day.ago) }
    let!(:old_scored) { create(:politician_profile, last_scored_at: 2.months.ago) }

    describe '.with_quality_score' do
      it 'returns politicians with quality scores' do
        expect(described_class.with_quality_score).to include(politician_with_score, low_quality, high_quality)
        expect(described_class.with_quality_score).not_to include(politician_without_score)
      end
    end

    describe '.high_quality' do
      it 'returns politicians with quality score >= 7.0 by default' do
        expect(described_class.high_quality).to include(politician_with_score, high_quality)
        expect(described_class.high_quality).not_to include(low_quality, politician_without_score)
      end

      it 'accepts custom minimum score' do
        expect(described_class.high_quality(9.0)).to eq([high_quality])
      end
    end

    describe '.recently_scored' do
      it 'returns politicians scored in the last month' do
        expect(described_class.recently_scored).to include(recently_scored)
        expect(described_class.recently_scored).not_to include(old_scored)
      end
    end
  end

  describe '#trades' do
    let(:politician) { create(:politician_profile, name: 'Nancy Pelosi') }
    let!(:pelosi_trade1) { create(:quiver_trade, trader_name: 'Nancy Pelosi', trader_source: 'congress') }
    let!(:pelosi_trade2) { create(:quiver_trade, trader_name: 'Nancy Pelosi', trader_source: 'congress') }
    let!(:other_trade) { create(:quiver_trade, trader_name: 'Other Person', trader_source: 'congress') }
    let!(:insider_trade) { create(:quiver_trade, trader_name: 'Nancy Pelosi', trader_source: 'insider') }

    it 'returns congressional trades for this politician' do
      expect(politician.trades).to include(pelosi_trade1, pelosi_trade2)
      expect(politician.trades).not_to include(other_trade, insider_trade)
    end
  end

  describe '#recent_trades' do
    let(:politician) { create(:politician_profile, name: 'Nancy Pelosi') }
    let!(:recent_trade) do
      create(:quiver_trade, trader_name: 'Nancy Pelosi', trader_source: 'congress',
                            transaction_date: 10.days.ago.to_date)
    end
    let!(:old_trade) do
      create(:quiver_trade, trader_name: 'Nancy Pelosi', trader_source: 'congress',
                            transaction_date: 60.days.ago.to_date)
    end

    it 'returns trades from the last 45 days by default' do
      expect(politician.recent_trades).to include(recent_trade)
      expect(politician.recent_trades).not_to include(old_trade)
    end

    it 'accepts custom lookback period' do
      expect(politician.recent_trades(30)).to include(recent_trade)
      expect(politician.recent_trades(5)).not_to include(recent_trade)
    end
  end

  describe '#win_rate' do
    it 'returns nil when total_trades is nil' do
      politician = build(:politician_profile, total_trades: nil)
      expect(politician.win_rate).to be_nil
    end

    it 'returns nil when total_trades is zero' do
      politician = build(:politician_profile, total_trades: 0)
      expect(politician.win_rate).to be_nil
    end

    it 'calculates percentage of winning trades' do
      politician = build(:politician_profile, total_trades: 10, winning_trades: 7)
      expect(politician.win_rate).to eq(70.0)
    end

    it 'rounds to 2 decimal places' do
      politician = build(:politician_profile, total_trades: 3, winning_trades: 2)
      expect(politician.win_rate).to eq(66.67)
    end
  end

  describe '#needs_scoring?' do
    it 'returns true when never scored' do
      politician = build(:politician_profile, last_scored_at: nil)
      expect(politician.needs_scoring?).to be true
    end

    it 'returns true when scored over a month ago' do
      politician = build(:politician_profile, last_scored_at: 2.months.ago)
      expect(politician.needs_scoring?).to be true
    end

    it 'returns false when scored recently' do
      politician = build(:politician_profile, last_scored_at: 1.day.ago)
      expect(politician.needs_scoring?).to be false
    end
  end

  describe '#has_committee_oversight?' do
    let(:politician) { create(:politician_profile) }
    let(:tech_industry) { create(:industry, name: 'Technology') }
    let(:healthcare_industry) { create(:industry, name: 'Healthcare') }
    let(:tech_committee) { create(:committee, code: 'HEC', name: 'Energy & Commerce') }

    before do
      create(:committee_industry_mapping, committee: tech_committee, industry: tech_industry)
      create(:committee_membership, politician_profile: politician, committee: tech_committee)
    end

    it 'returns true when politician has oversight for the industry' do
      expect(politician.has_committee_oversight?(['Technology'])).to be true
    end

    it 'returns false when politician has no oversight for the industry' do
      expect(politician.has_committee_oversight?(['Healthcare'])).to be false
    end

    it 'returns false when politician has no committees' do
      politician_no_committees = create(:politician_profile)
      expect(politician_no_committees.has_committee_oversight?(['Technology'])).to be false
    end

    it 'handles multiple industries' do
      expect(politician.has_committee_oversight?(%w[Technology Healthcare])).to be true
    end
  end
end
