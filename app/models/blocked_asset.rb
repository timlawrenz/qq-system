# frozen_string_literal: true

# BlockedAsset tracks assets that failed to trade due to being inactive,
# non-tradable, or non-fractionable in Alpaca. These assets are automatically
# filtered from target portfolios to prevent repeated trade failures.
#
# Blocked assets expire after 7 days and are automatically cleaned up,
# allowing the system to retry them in case they become tradable again.
class BlockedAsset < ApplicationRecord
  EXPIRATION_DAYS = 7

  validates :symbol, presence: true, uniqueness: true
  validates :reason, presence: true
  validates :blocked_at, presence: true
  validates :expires_at, presence: true

  # Scopes
  scope :active, -> { where('expires_at > ?', Time.current) }
  scope :expired, -> { where(expires_at: ..Time.current) }

  # Class methods
  def self.blocked_symbols
    active.pluck(:symbol)
  end

  def self.block_asset(symbol:, reason:)
    create!(
      symbol: symbol,
      reason: reason,
      blocked_at: Time.current,
      expires_at: EXPIRATION_DAYS.days.from_now
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    # Asset already blocked, update the expiration
    raise e if e.is_a?(ActiveRecord::RecordInvalid) && e.message.exclude?('Symbol has already been taken')

    asset = find_by(symbol: symbol)
    if asset
      asset.update!(expires_at: EXPIRATION_DAYS.days.from_now, reason: reason)
      asset
    end
  end

  def self.cleanup_expired
    deleted_count = expired.delete_all
    Rails.logger.info("Cleaned up #{deleted_count} expired blocked assets") if deleted_count.positive?
    deleted_count
  end

  # Instance methods
  def expired?
    expires_at <= Time.current
  end

  def days_until_expiration
    return 0 if expired?

    ((expires_at - Time.current) / 1.day).ceil
  end
end
