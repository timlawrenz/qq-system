# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Committee, type: :model do
  describe 'associations' do
    it 'has many committee_memberships' do
      expect(subject).to respond_to(:committee_memberships)
    end

    it 'has many politician_profiles through committee_memberships' do
      expect(subject).to respond_to(:politician_profiles)
    end

    it 'has many committee_industry_mappings' do
      expect(subject).to respond_to(:committee_industry_mappings)
    end

    it 'has many industries through committee_industry_mappings' do
      expect(subject).to respond_to(:industries)
    end
  end

  describe 'validations' do
    it 'validates presence of code' do
      committee = build(:committee, code: nil)
      expect(committee).not_to be_valid
      expect(committee.errors[:code]).to include("can't be blank")
    end

    it 'validates presence of name' do
      committee = build(:committee, name: nil)
      expect(committee).not_to be_valid
      expect(committee.errors[:name]).to include("can't be blank")
    end

    it 'validates uniqueness of code' do
      create(:committee, code: 'HEC')
      duplicate = build(:committee, code: 'HEC')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:code]).to include('has already been taken')
    end

    it 'validates chamber is house, senate, or joint' do
      committee = build(:committee, chamber: 'invalid')
      expect(committee).not_to be_valid
      expect(committee.errors[:chamber]).to include('is not included in the list')
    end

    it 'allows house chamber' do
      committee = build(:committee, chamber: 'house')
      expect(committee).to be_valid
    end

    it 'allows senate chamber' do
      committee = build(:committee, chamber: 'senate')
      expect(committee).to be_valid
    end

    it 'allows joint chamber' do
      committee = build(:committee, chamber: 'joint')
      expect(committee).to be_valid
    end

    it 'allows nil chamber' do
      committee = build(:committee, chamber: nil)
      expect(committee).to be_valid
    end
  end

  describe 'scopes' do
    let!(:house_committee1) { create(:committee, :house, code: 'HEC', name: 'Energy & Commerce') }
    let!(:house_committee2) { create(:committee, :house, code: 'HAG', name: 'Agriculture') }
    let!(:senate_committee) { create(:committee, :senate, code: 'SFN', name: 'Finance') }
    let!(:tech_industry) { create(:industry, :technology) }

    before do
      create(:committee_industry_mapping, committee: house_committee1, industry: tech_industry)
    end

    describe '.house_committees' do
      it 'returns only house committees' do
        expect(described_class.house_committees).to include(house_committee1, house_committee2)
        expect(described_class.house_committees).not_to include(senate_committee)
      end
    end

    describe '.senate_committees' do
      it 'returns only senate committees' do
        expect(described_class.senate_committees).to include(senate_committee)
        expect(described_class.senate_committees).not_to include(house_committee1, house_committee2)
      end
    end

    describe '.with_industry_oversight' do
      it 'returns committees with oversight for the industry' do
        result = described_class.with_industry_oversight('Technology')
        expect(result).to include(house_committee1)
        expect(result).not_to include(house_committee2, senate_committee)
      end

      it 'returns empty when no committees have oversight' do
        result = described_class.with_industry_oversight('Nonexistent Industry')
        expect(result).to be_empty
      end
    end
  end

  describe '#has_oversight_of?' do
    let(:committee) { create(:committee, code: 'HEC', name: 'Energy & Commerce') }
    let(:tech_industry) { create(:industry, name: 'Technology') }
    let(:healthcare_industry) { create(:industry, name: 'Healthcare') }

    before do
      create(:committee_industry_mapping, committee: committee, industry: tech_industry)
    end

    it 'returns true for single industry with oversight' do
      expect(committee.has_oversight_of?('Technology')).to be true
    end

    it 'returns false for single industry without oversight' do
      expect(committee.has_oversight_of?('Healthcare')).to be false
    end

    it 'returns true when array contains industry with oversight' do
      expect(committee.has_oversight_of?(['Technology', 'Healthcare'])).to be true
    end

    it 'returns false when array has no industries with oversight' do
      expect(committee.has_oversight_of?(['Healthcare', 'Finance'])).to be false
    end

    it 'handles string argument' do
      expect(committee.has_oversight_of?('Technology')).to be true
    end

    it 'handles array argument' do
      expect(committee.has_oversight_of?(['Technology'])).to be true
    end
  end

  describe '#display_name' do
    it 'returns House prefixed name for house committee' do
      committee = build(:committee, chamber: 'house', name: 'Energy & Commerce')
      expect(committee.display_name).to eq('House Energy & Commerce')
    end

    it 'returns Senate prefixed name for senate committee' do
      committee = build(:committee, chamber: 'senate', name: 'Finance')
      expect(committee.display_name).to eq('Senate Finance')
    end

    it 'returns Joint prefixed name for joint committee' do
      committee = build(:committee, chamber: 'joint', name: 'Taxation')
      expect(committee.display_name).to eq('Joint Taxation')
    end

    it 'returns plain name when chamber is nil' do
      committee = build(:committee, chamber: nil, name: 'Special Committee')
      expect(committee.display_name).to eq('Special Committee')
    end

    it 'strips extra whitespace' do
      committee = build(:committee, chamber: nil, name: 'Test Committee')
      expect(committee.display_name).to eq('Test Committee')
    end
  end
end
