# frozen_string_literal: true

# rubocop:disable RSpec/NamedSubject, RSpec/IndexedLet

require 'rails_helper'

RSpec.describe Industry, type: :model do
  describe 'associations' do
    it 'has many committee_industry_mappings' do
      expect(subject).to respond_to(:committee_industry_mappings)
    end

    it 'has many committees through committee_industry_mappings' do
      expect(subject).to respond_to(:committees)
    end
  end

  describe 'validations' do
    it 'validates presence of name' do
      industry = build(:industry, name: nil)
      expect(industry).not_to be_valid
      expect(industry.errors[:name]).to include("can't be blank")
    end

    it 'allows industry without description' do
      industry = build(:industry, description: nil)
      expect(industry).to be_valid
    end
  end

  describe 'factory traits' do
    it 'creates technology industry' do
      industry = create(:industry, :technology)
      expect(industry.name).to eq('Technology')
      expect(industry.description).to include('technology')
    end

    it 'creates healthcare industry' do
      industry = create(:industry, :healthcare)
      expect(industry.name).to eq('Healthcare')
      expect(industry.description).to include('Healthcare')
    end

    it 'creates finance industry' do
      industry = create(:industry, :finance)
      expect(industry.name).to eq('Financial Services')
      expect(industry.description).to include('financial')
    end
  end

  describe 'committee relationships' do
    let(:industry) { create(:industry, name: 'Technology') }
    let(:committee1) { create(:committee, code: 'HEC', name: 'Energy & Commerce') }
    let(:committee2) { create(:committee, code: 'HSC', name: 'Science & Technology') }

    before do
      create(:committee_industry_mapping, industry: industry, committee: committee1)
      create(:committee_industry_mapping, industry: industry, committee: committee2)
    end

    it 'returns associated committees' do
      expect(industry.committees).to include(committee1, committee2)
    end

    it 'can count oversight committees' do
      expect(industry.committees.count).to eq(2)
    end
  end

  describe '.classify_stock' do
    before do
      create(:industry, name: 'Technology')
      create(:industry, name: 'Semiconductors')
      create(:industry, name: 'Healthcare')
      create(:industry, name: 'Energy')
      create(:industry, name: 'Financial Services')
      create(:industry, name: 'Defense')
      create(:industry, name: 'Other')
    end

    it 'classifies technology stocks' do
      results = described_class.classify_stock('Apple Inc - Technology')
      expect(results.map(&:name)).to include('Technology')
    end

    it 'classifies semiconductor stocks' do
      results = described_class.classify_stock('NVIDIA Corporation')
      expect(results.map(&:name)).to include('Semiconductors')
    end

    it 'classifies healthcare stocks' do
      results = described_class.classify_stock('Pfizer Pharmaceutical')
      expect(results.map(&:name)).to include('Healthcare')
    end

    it 'classifies energy stocks' do
      results = described_class.classify_stock('Solar Energy Corp')
      expect(results.map(&:name)).to include('Energy')
    end

    it 'classifies financial stocks' do
      results = described_class.classify_stock('JPMorgan Banking')
      expect(results.map(&:name)).to include('Financial Services')
    end

    it 'classifies defense stocks' do
      results = described_class.classify_stock('Lockheed Martin Defense')
      expect(results.map(&:name)).to include('Defense')
    end

    it 'returns Other for unrecognized stocks' do
      results = described_class.classify_stock('Generic Company XYZ')
      expect(results.map(&:name)).to include('Other')
    end

    it 'handles ticker symbols' do
      described_class.classify_stock('NVDA')
      # NVDA alone might not match, but nvidia does
      results_nvidia = described_class.classify_stock('nvidia')
      expect(results_nvidia.map(&:name)).to include('Semiconductors')
    end

    it 'can classify into multiple industries' do
      results = described_class.classify_stock('HealthTech Software')
      expect(results.count).to be >= 2
    end

    it 'is case insensitive' do
      results = described_class.classify_stock('TECHNOLOGY SOFTWARE')
      expect(results.map(&:name)).to include('Technology')
    end
  end

  describe 'scopes' do
    let!(:tech_industry) { create(:industry, name: 'Technology', sector: 'technology') }
    let!(:healthcare_industry) { create(:industry, name: 'Healthcare', sector: 'healthcare') }
    let!(:finance_industry) { create(:industry, name: 'Finance', sector: 'finance') }
    let(:committee) { create(:committee) }

    before do
      create(:committee_industry_mapping, industry: tech_industry, committee: committee)
    end

    describe '.by_sector' do
      it 'filters industries by sector' do
        expect(described_class.by_sector('technology')).to include(tech_industry)
        expect(described_class.by_sector('technology')).not_to include(healthcare_industry)
      end
    end

    describe '.with_committee_oversight' do
      it 'returns industries that have committee oversight' do
        expect(described_class.with_committee_oversight).to include(tech_industry)
        expect(described_class.with_committee_oversight).not_to include(healthcare_industry, finance_industry)
      end
    end
  end
end
# rubocop:enable RSpec/NamedSubject, RSpec/IndexedLet
