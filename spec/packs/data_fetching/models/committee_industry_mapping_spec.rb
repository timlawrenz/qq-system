# frozen_string_literal: true

# rubocop:disable RSpec/NamedSubject

require 'rails_helper'

RSpec.describe CommitteeIndustryMapping, type: :model do
  describe 'associations' do
    it 'belongs to committee' do
      expect(subject).to respond_to(:committee)
    end

    it 'belongs to industry' do
      expect(subject).to respond_to(:industry)
    end
  end

  describe 'validations' do
    let(:committee) { create(:committee) }
    let(:industry) { create(:industry) }

    it 'validates uniqueness of committee scoped to industry' do
      create(:committee_industry_mapping, committee: committee, industry: industry)
      duplicate = build(:committee_industry_mapping, committee: committee, industry: industry)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:committee_id]).to include('has already been taken')
    end

    it 'allows same committee with different industry' do
      industry2 = create(:industry, name: 'Healthcare')
      create(:committee_industry_mapping, committee: committee, industry: industry)
      different_industry = build(:committee_industry_mapping, committee: committee, industry: industry2)

      expect(different_industry).to be_valid
    end

    it 'allows same industry with different committee' do
      committee2 = create(:committee, code: 'HSC')
      create(:committee_industry_mapping, committee: committee, industry: industry)
      different_committee = build(:committee_industry_mapping, committee: committee2, industry: industry)

      expect(different_committee).to be_valid
    end
  end

  describe 'join table behavior' do
    let(:committee) { create(:committee, code: 'HEC', name: 'Energy & Commerce') }
    let(:tech_industry) { create(:industry, name: 'Technology') }
    let(:healthcare_industry) { create(:industry, name: 'Healthcare') }

    it 'links committee to industries' do
      create(:committee_industry_mapping, committee: committee, industry: tech_industry)
      create(:committee_industry_mapping, committee: committee, industry: healthcare_industry)

      expect(committee.industries).to include(tech_industry, healthcare_industry)
    end

    it 'links industry to committees' do
      committee2 = create(:committee, code: 'HSC', name: 'Science')
      create(:committee_industry_mapping, committee: committee, industry: tech_industry)
      create(:committee_industry_mapping, committee: committee2, industry: tech_industry)

      expect(tech_industry.committees).to include(committee, committee2)
    end
  end
end
# rubocop:enable RSpec/NamedSubject
