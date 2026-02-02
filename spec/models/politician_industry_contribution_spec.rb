require 'rails_helper'

RSpec.describe PoliticianIndustryContribution, type: :model do
  describe 'associations' do
    it 'belongs to politician_profile' do
      expect(described_class.reflect_on_association(:politician_profile).macro).to eq(:belongs_to)
    end

    it 'belongs to industry' do
      expect(described_class.reflect_on_association(:industry).macro).to eq(:belongs_to)
    end
  end

  describe 'validations' do
    let(:contribution) { build(:politician_industry_contribution) }

    it 'validates presence of cycle' do
      contribution.cycle = nil
      expect(contribution).not_to be_valid
      expect(contribution.errors[:cycle]).to include("can't be blank")
    end

    it 'validates total_amount is greater than or equal to 0' do
      contribution.total_amount = -1
      expect(contribution).not_to be_valid
    end

    it 'validates contribution_count is greater than or equal to 0' do
      contribution.contribution_count = -1
      expect(contribution).not_to be_valid
    end

    it 'validates employer_count is greater than or equal to 0' do
      contribution.employer_count = -1
      expect(contribution).not_to be_valid
    end
  end

  describe 'scopes' do
    let!(:politician) { create(:politician_profile) }
    let!(:industry_tech) { create(:industry, name: 'Technology') }
    let!(:industry_health) { create(:industry, name: 'Healthcare') }
    
    let!(:current_contribution) do
      create(:politician_industry_contribution,
             politician_profile: politician,
             industry: industry_tech,
             cycle: 2024,
             total_amount: 50_000)
    end
    let!(:old_contribution) do
      create(:politician_industry_contribution,
             politician_profile: politician,
             industry: industry_tech,
             cycle: 2022,
             total_amount: 20_000)
    end
    let!(:small_contribution) do
      create(:politician_industry_contribution,
             politician_profile: politician,
             industry: industry_health,
             cycle: 2024,
             total_amount: 5_000)
    end

    describe '.current_cycle' do
      it 'returns only 2024 cycle contributions' do
        expect(described_class.current_cycle).to include(current_contribution, small_contribution)
        expect(described_class.current_cycle).not_to include(old_contribution)
      end
    end

    describe '.significant' do
      it 'returns only contributions >= $10,000' do
        expect(described_class.significant).to include(current_contribution, old_contribution)
        expect(described_class.significant).not_to include(small_contribution)
      end
    end
  end

  describe '#influence_score' do
    let(:politician) { create(:politician_profile) }
    let(:industry) { create(:industry, name: 'Technology') }

    it 'returns 0 for zero amount' do
      contribution = build(:politician_industry_contribution,
                           politician_profile: politician,
                           industry: industry,
                           total_amount: 0,
                           contribution_count: 100)
      expect(contribution.influence_score).to eq(0)
    end

    it 'calculates score for typical contribution' do
      contribution = build(:politician_industry_contribution,
                           politician_profile: politician,
                           industry: industry,
                           total_amount: 50_000,
                           contribution_count: 200)
      score = contribution.influence_score
      expect(score).to be > 0
      expect(score).to be <= 10
    end

    it 'caps score at 10' do
      contribution = build(:politician_industry_contribution,
                           politician_profile: politician,
                           industry: industry,
                           total_amount: 10_000_000,
                           contribution_count: 10_000)
      expect(contribution.influence_score).to eq(10.0)
    end

    it 'returns higher scores for higher amounts and counts' do
      low_contribution = build(:politician_industry_contribution,
                               politician_profile: politician,
                               industry: industry,
                               total_amount: 10_000,
                               contribution_count: 50)
      high_contribution = build(:politician_industry_contribution,
                                politician_profile: politician,
                                industry: industry,
                                total_amount: 100_000,
                                contribution_count: 500)

      expect(high_contribution.influence_score).to be > low_contribution.influence_score
    end
  end

  describe '#weight_multiplier' do
    let(:politician) { create(:politician_profile) }
    let(:industry) { create(:industry, name: 'Technology') }

    it 'returns 1.0 for zero influence score' do
      contribution = build(:politician_industry_contribution,
                           politician_profile: politician,
                           industry: industry,
                           total_amount: 0,
                           contribution_count: 0)
      expect(contribution.weight_multiplier).to eq(1.0)
    end

    it 'returns values between 1.0 and 2.0' do
      contribution = build(:politician_industry_contribution,
                           politician_profile: politician,
                           industry: industry,
                           total_amount: 50_000,
                           contribution_count: 200)
      multiplier = contribution.weight_multiplier
      expect(multiplier).to be >= 1.0
      expect(multiplier).to be <= 2.0
    end

    it 'returns 2.0 for maximum influence score' do
      contribution = build(:politician_industry_contribution,
                           politician_profile: politician,
                           industry: industry,
                           total_amount: 5_000_000,
                           contribution_count: 1000)
      expect(contribution.weight_multiplier).to eq(2.0)
    end
  end
end
