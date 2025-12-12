# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BlockedAsset, type: :model do
  describe 'validations' do
    it 'validates presence of symbol' do
      asset = described_class.new(reason: 'test', blocked_at: Time.current, expires_at: 1.day.from_now)
      expect(asset).not_to be_valid
      expect(asset.errors[:symbol]).to include("can't be blank")
    end

    it 'validates presence of reason' do
      asset = described_class.new(symbol: 'TEST', blocked_at: Time.current, expires_at: 1.day.from_now)
      expect(asset).not_to be_valid
      expect(asset.errors[:reason]).to include("can't be blank")
    end

    it 'validates presence of blocked_at' do
      asset = described_class.new(symbol: 'TEST', reason: 'test', expires_at: 1.day.from_now)
      expect(asset).not_to be_valid
      expect(asset.errors[:blocked_at]).to include("can't be blank")
    end

    it 'validates presence of expires_at' do
      asset = described_class.new(symbol: 'TEST', reason: 'test', blocked_at: Time.current)
      expect(asset).not_to be_valid
      expect(asset.errors[:expires_at]).to include("can't be blank")
    end

    it 'validates uniqueness of symbol' do
      described_class.create!(
        symbol: 'TEST',
        reason: 'asset_not_active',
        blocked_at: Time.current,
        expires_at: 7.days.from_now
      )

      duplicate = described_class.new(
        symbol: 'TEST',
        reason: 'another_reason',
        blocked_at: Time.current,
        expires_at: 7.days.from_now
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:symbol]).to include('has already been taken')
    end
  end

  describe 'scopes' do
    before do
      # Active (not expired)
      described_class.create!(
        symbol: 'ACTIVE1',
        reason: 'asset_not_active',
        blocked_at: 1.day.ago,
        expires_at: 5.days.from_now
      )
      described_class.create!(
        symbol: 'ACTIVE2',
        reason: 'asset_not_active',
        blocked_at: Time.current,
        expires_at: 6.days.from_now
      )

      # Expired
      described_class.create!(
        symbol: 'EXPIRED1',
        reason: 'asset_not_active',
        blocked_at: 10.days.ago,
        expires_at: 2.days.ago
      )
      described_class.create!(
        symbol: 'EXPIRED2',
        reason: 'asset_not_active',
        blocked_at: 8.days.ago,
        expires_at: 1.hour.ago
      )
    end

    describe '.active' do
      it 'returns only non-expired assets' do
        active = described_class.active
        expect(active.pluck(:symbol)).to contain_exactly('ACTIVE1', 'ACTIVE2')
      end
    end

    describe '.expired' do
      it 'returns only expired assets' do
        expired = described_class.expired
        expect(expired.pluck(:symbol)).to contain_exactly('EXPIRED1', 'EXPIRED2')
      end
    end
  end

  describe '.blocked_symbols' do
    it 'returns symbols of active blocked assets' do
      described_class.create!(
        symbol: 'BLOCKED1',
        reason: 'asset_not_active',
        blocked_at: Time.current,
        expires_at: 5.days.from_now
      )
      described_class.create!(
        symbol: 'BLOCKED2',
        reason: 'asset_not_active',
        blocked_at: Time.current,
        expires_at: 3.days.from_now
      )

      # Expired asset should not be included
      described_class.create!(
        symbol: 'EXPIRED',
        reason: 'asset_not_active',
        blocked_at: 10.days.ago,
        expires_at: 1.day.ago
      )

      expect(described_class.blocked_symbols).to contain_exactly('BLOCKED1', 'BLOCKED2')
    end

    it 'returns empty array when no active blocked assets' do
      expect(described_class.blocked_symbols).to eq([])
    end
  end

  describe '.block_asset' do
    it 'creates a new blocked asset with 7-day expiration' do
      asset = described_class.block_asset(symbol: 'NEWASSET', reason: 'asset_not_active')

      expect(asset).to be_persisted
      expect(asset.symbol).to eq('NEWASSET')
      expect(asset.reason).to eq('asset_not_active')
      expect(asset.blocked_at).to be_within(1.second).of(Time.current)
      expect(asset.expires_at).to be_within(1.second).of(7.days.from_now)
    end

    it 'updates expiration if asset already blocked' do
      # Create initial blocked asset
      initial = described_class.block_asset(symbol: 'TEST', reason: 'original_reason')
      initial_expires = initial.expires_at

      # Wait a moment then block again
      sleep 0.1
      updated = described_class.block_asset(symbol: 'TEST', reason: 'updated_reason')

      expect(described_class.count).to eq(1)
      expect(updated.expires_at).to be > initial_expires
      expect(updated.expires_at).to be_within(2.seconds).of(7.days.from_now)
      expect(updated.reason).to eq('updated_reason')
    end
  end

  describe '.cleanup_expired' do
    it 'deletes expired blocked assets' do
      # Active assets
      described_class.create!(
        symbol: 'ACTIVE',
        reason: 'asset_not_active',
        blocked_at: Time.current,
        expires_at: 5.days.from_now
      )

      # Expired assets
      described_class.create!(
        symbol: 'EXPIRED1',
        reason: 'asset_not_active',
        blocked_at: 10.days.ago,
        expires_at: 2.days.ago
      )
      described_class.create!(
        symbol: 'EXPIRED2',
        reason: 'asset_not_active',
        blocked_at: 8.days.ago,
        expires_at: 1.hour.ago
      )

      expect do
        deleted_count = described_class.cleanup_expired
        expect(deleted_count).to eq(2)
      end.to change(described_class, :count).from(3).to(1)

      expect(described_class.pluck(:symbol)).to eq(['ACTIVE'])
    end

    it 'returns 0 when no expired assets' do
      described_class.create!(
        symbol: 'ACTIVE',
        reason: 'asset_not_active',
        blocked_at: Time.current,
        expires_at: 5.days.from_now
      )

      count = described_class.cleanup_expired
      expect(count).to eq(0)
      expect(described_class.count).to eq(1)
    end
  end

  describe '#expired?' do
    it 'returns true for expired asset' do
      asset = described_class.create!(
        symbol: 'TEST',
        reason: 'asset_not_active',
        blocked_at: 10.days.ago,
        expires_at: 1.day.ago
      )

      expect(asset.expired?).to be true
    end

    it 'returns false for active asset' do
      asset = described_class.create!(
        symbol: 'TEST',
        reason: 'asset_not_active',
        blocked_at: Time.current,
        expires_at: 5.days.from_now
      )

      expect(asset.expired?).to be false
    end
  end

  describe '#days_until_expiration' do
    it 'returns number of days until expiration' do
      asset = described_class.create!(
        symbol: 'TEST',
        reason: 'asset_not_active',
        blocked_at: Time.current,
        expires_at: 5.days.from_now
      )

      expect(asset.days_until_expiration).to eq(5)
    end

    it 'returns 0 for expired asset' do
      asset = described_class.create!(
        symbol: 'TEST',
        reason: 'asset_not_active',
        blocked_at: 10.days.ago,
        expires_at: 1.day.ago
      )

      expect(asset.days_until_expiration).to eq(0)
    end
  end
end
