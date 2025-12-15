# frozen_string_literal: true

module Maintenance
  # CleanupBlockedAssets
  #
  # Small GLCommand wrapper around BlockedAsset.cleanup_expired so it can be
  # composed in chains and called from jobs or rake tasks.
  class CleanupBlockedAssets < GLCommand::Callable
    returns :removed_count

    def call
      removed = BlockedAsset.cleanup_expired
      context.removed_count = removed
    rescue StandardError => e
      stop_and_fail!(e.message)
    end
  end
end
