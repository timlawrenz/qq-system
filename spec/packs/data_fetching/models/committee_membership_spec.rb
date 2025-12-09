# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CommitteeMembership, type: :model do
  describe 'associations' do
    it 'belongs to politician_profile' do
      expect(subject).to respond_to(:politician_profile)
    end

    it 'belongs to committee' do
      expect(subject).to respond_to(:committee)
    end
  end

  describe 'validations' do
    let(:politician) { create(:politician_profile) }
    let(:committee) { create(:committee) }

    it 'validates uniqueness of politician_profile scoped to committee' do
      create(:committee_membership, politician_profile: politician, committee: committee)
      duplicate = build(:committee_membership, politician_profile: politician, committee: committee)
      
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:politician_profile_id]).to include('has already been taken')
    end

    it 'allows same politician on different committees' do
      committee2 = create(:committee, code: 'HSC')
      create(:committee_membership, politician_profile: politician, committee: committee)
      different_committee = build(:committee_membership, politician_profile: politician, committee: committee2)
      
      expect(different_committee).to be_valid
    end

    it 'validates end_date is after start_date' do
      membership = build(:committee_membership,
        start_date: Date.parse('2024-01-01'),
        end_date: Date.parse('2023-12-01'))
      
      expect(membership).not_to be_valid
      expect(membership.errors[:end_date]).to include('must be after start date')
    end

    it 'allows nil end_date' do
      membership = build(:committee_membership, start_date: Date.parse('2024-01-01'), end_date: nil)
      expect(membership).to be_valid
    end

    it 'allows end_date after start_date' do
      membership = build(:committee_membership,
        start_date: Date.parse('2024-01-01'),
        end_date: Date.parse('2024-12-31'))
      
      expect(membership).to be_valid
    end
  end

  describe 'scopes' do
    let(:politician) { create(:politician_profile) }
    let(:committee) { create(:committee) }
    
    let!(:active_membership) do
      create(:committee_membership, :active,
        politician_profile: politician,
        committee: committee,
        start_date: 1.year.ago)
    end
    
    let!(:historical_membership) do
      create(:committee_membership, :expired,
        politician_profile: create(:politician_profile),
        committee: committee,
        start_date: 2.years.ago,
        end_date: 6.months.ago)
    end

    describe '.active' do
      it 'returns memberships with no end_date' do
        expect(described_class.active).to include(active_membership)
      end

      it 'excludes historical memberships' do
        expect(described_class.active).not_to include(historical_membership)
      end
    end

    describe '.historical' do
      it 'returns memberships that have ended' do
        expect(described_class.historical).to include(historical_membership)
      end

      it 'excludes active memberships' do
        expect(described_class.historical).not_to include(active_membership)
      end
    end

    describe '.on_date' do
      it 'returns memberships active on specific date' do
        date = 1.month.ago
        results = described_class.on_date(date)
        expect(results).to include(active_membership)
      end

      it 'excludes memberships that ended before date' do
        date = 1.month.ago
        results = described_class.on_date(date)
        expect(results).not_to include(historical_membership)
      end

      it 'includes memberships active on the date' do
        membership = create(:committee_membership,
          politician_profile: create(:politician_profile),
          committee: committee,
          start_date: 2.years.ago,
          end_date: 1.month.from_now)
        
        results = described_class.on_date(Date.current)
        expect(results).to include(membership)
      end
    end
  end

  describe '#active?' do
    it 'returns true when end_date is nil' do
      membership = build(:committee_membership, end_date: nil)
      expect(membership.active?).to be true
    end

    it 'returns true when end_date is in the future' do
      membership = build(:committee_membership, end_date: 1.month.from_now.to_date)
      expect(membership.active?).to be true
    end

    it 'returns false when end_date is in the past' do
      membership = build(:committee_membership, end_date: 1.month.ago.to_date)
      expect(membership.active?).to be false
    end

    it 'returns true when end_date is today' do
      membership = build(:committee_membership, end_date: Date.current)
      expect(membership.active?).to be true
    end
  end
end
