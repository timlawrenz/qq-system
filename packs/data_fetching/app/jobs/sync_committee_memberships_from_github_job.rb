# frozen_string_literal: true

class SyncCommitteeMembershipsFromGithubJob < ApplicationJob
  queue_as :default
  
  def perform
    Rails.logger.info "Starting committee membership sync from GitHub..."
    
    result = SyncCommitteeMembershipsFromGithub.call
    
    if result.success?
      stats = result.value
      Rails.logger.info "✓ Synced #{stats[:memberships_created]} memberships from GitHub"
      Rails.logger.info "  Committees: #{stats[:committees_processed]}"
      Rails.logger.info "  Matched: #{stats[:politicians_matched]} politicians"
      Rails.logger.info "  Unmatched: #{stats[:politicians_unmatched].count} politicians"
      
      if stats[:politicians_unmatched].any? && stats[:politicians_unmatched].count < 20
        Rails.logger.warn "  Unmatched politicians: #{stats[:politicians_unmatched].join(', ')}"
      end
    else
      Rails.logger.error "✗ Committee sync failed: #{result.error}"
      raise result.error
    end
  end
end
