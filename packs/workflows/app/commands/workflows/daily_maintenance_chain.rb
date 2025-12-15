# frozen_string_literal: true

module Workflows
  # DailyMaintenanceChain
  #
  # Runs all daily maintenance-style commands in a single GLCommand chain.
  # For now this includes:
  # - FetchInsiderTrades (loads recent insider data into quiver_trades)
  # - Maintenance::CleanupBlockedAssets (expires old blocked assets)
  class DailyMaintenanceChain < GLCommand::Chainable
    # Expose a small, stable set of returns at the chain level
    returns :total_count, :new_count, :updated_count, :error_count, :removed_count

    chain FetchInsiderTrades, Maintenance::CleanupBlockedAssets
  end
end
