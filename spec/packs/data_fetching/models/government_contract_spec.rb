# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GovernmentContract do
  describe 'validations' do
    it 'requires required fields' do
      record = described_class.new
      expect(record).not_to be_valid
      expect(record.errors[:contract_id]).to be_present
      expect(record.errors[:ticker]).to be_present
      expect(record.errors[:award_date]).to be_present
      expect(record.errors[:contract_value]).to be_present
    end

    it 'requires positive contract_value' do
      record = described_class.new(
        contract_id: 'C1',
        ticker: 'LMT',
        award_date: Date.current,
        contract_value: 0
      )

      expect(record).not_to be_valid
      expect(record.errors[:contract_value]).to be_present
    end
  end

  describe 'scopes' do
    let!(:recent_contract) do
      described_class.create!(
        contract_id: 'RECENT',
        ticker: 'LMT',
        company: 'Lockheed Martin',
        contract_value: 25_000_000,
        award_date: 2.days.ago.to_date,
        agency: 'Department of Defense'
      )
    end

    let!(:old_contract) do
      described_class.create!(
        contract_id: 'OLD',
        ticker: 'LMT',
        company: 'Lockheed Martin',
        contract_value: 25_000_000,
        award_date: 200.days.ago.to_date,
        agency: 'Department of Defense'
      )
    end

    it 'filters by recent' do
      expect(described_class.recent(7)).to contain_exactly(recent_contract)
      expect(described_class.recent(7)).not_to include(old_contract)
    end

    it 'filters by ticker and agency' do
      expect(described_class.for_ticker('LMT').by_agency('Department of Defense')).to include(recent_contract)
    end

    it 'filters by minimum value' do
      expect(described_class.minimum_value(10_000_000)).to include(recent_contract)
    end
  end
end
