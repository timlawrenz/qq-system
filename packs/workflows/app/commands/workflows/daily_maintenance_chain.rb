# frozen_string_literal: true

module Workflows
  # DailyMaintenanceChain
  #
  # Runs all daily maintenance-style commands in a single GLCommand.
  # Orchestrates data fetching, syncing, scoring, and cleanup.
  class DailyMaintenanceChain < GLCommand::Callable
    returns :quiver_stats, :insider_stats, :contracts_stats, :lobbying_stats,
            :committee_stats, :scoring_stats, :cleanup_stats, :profile_stats,
            # Legacy/Root keys for backward compatibility or ease of access if needed
            :trades_count, :new_trades_count, :updated_trades_count, # Quiver (Congressional)
            :total_count, :new_count, :updated_count, # Insider (legacy keys)
            :removed_count, # Cleanup
            :tickers_seen, :profiles_refreshed, :profiles_skipped, :profiles_failed # Profiles

    def call
      run_congressional_fetch
      run_insider_fetch
      run_contracts_fetch
      run_lobbying_fetch
      run_committee_sync
      run_politician_scoring
      run_cleanup
      run_profile_refresh
    end

    private

    def run_congressional_fetch
      Rails.logger.info("[DailyMaintenanceChain] Running FetchQuiverData...")
      result = FetchQuiverData.call!
      
      context.quiver_stats = {
        fetched: result.trades_count,
        created: result.new_trades_count,
        updated: result.updated_trades_count
      }
      # Maintain legacy keys
      context.trades_count = result.trades_count
      context.new_trades_count = result.new_trades_count
      context.updated_trades_count = result.updated_trades_count
    end

    def run_insider_fetch
      Rails.logger.info("[DailyMaintenanceChain] Running FetchInsiderTrades...")
      result = FetchInsiderTrades.call!
      
      context.insider_stats = {
        fetched: result.total_count,
        created: result.new_count,
        updated: result.updated_count
      }
      # Maintain legacy keys
      context.total_count = result.total_count
      context.new_count = result.new_count
      context.updated_count = result.updated_count
    end

    def run_contracts_fetch
      Rails.logger.info("[DailyMaintenanceChain] Running FetchGovernmentContracts...")
      result = FetchGovernmentContracts.call!
      
      context.contracts_stats = {
        fetched: result.total_count,
        created: result.new_count,
        updated: result.updated_count
      }
    end

    def run_lobbying_fetch
      Rails.logger.info("[DailyMaintenanceChain] Running FetchLobbyingData...")
      result = FetchLobbyingData.call!
      
      context.lobbying_stats = {
        total: result.total_records,
        new: result.new_records,
        updated: result.updated_records,
        tickers_processed: result.tickers_processed
      }
    end

    def run_committee_sync
      Rails.logger.info("[DailyMaintenanceChain] Running SyncCommitteeMembershipsFromGithub...")
      result = SyncCommitteeMembershipsFromGithub.call!
      
      # Fix: Access individual return keys instead of non-existent .value
      context.committee_stats = {
        committees_processed: result.committees_processed,
        memberships_created: result.memberships_created,
        politicians_matched: result.politicians_matched,
        politicians_unmatched: result.politicians_unmatched
      }
    end

    def run_politician_scoring
      Rails.logger.info("[DailyMaintenanceChain] Running ScoreAllPoliticians...")
      result = ScoreAllPoliticians.call!
      
      context.scoring_stats = {
        profiles: result.profiles_count,
        scored: result.scored_count,
        created: result.created_count
      }
    end

    def run_cleanup
      Rails.logger.info("[DailyMaintenanceChain] Running Maintenance::CleanupBlockedAssets...")
      result = Maintenance::CleanupBlockedAssets.call!
      
      context.cleanup_stats = { removed: result.removed_count }
      context.removed_count = result.removed_count
    end

    def run_profile_refresh
      Rails.logger.info("[DailyMaintenanceChain] Running TradingStrategies::RefreshCompanyProfiles...")
      result = TradingStrategies::RefreshCompanyProfiles.call!
      
      context.profile_stats = {
        tickers_seen: result.tickers_seen,
        refreshed: result.profiles_refreshed,
        skipped: result.profiles_skipped,
        failed: result.profiles_failed
      }
      context.tickers_seen = result.tickers_seen
      context.profiles_refreshed = result.profiles_refreshed
      context.profiles_skipped = result.profiles_skipped
      context.profiles_failed = result.profiles_failed
    end
  end
end