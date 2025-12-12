# frozen_string_literal: true

namespace :blocked_assets do
  desc 'Clean up expired blocked assets (older than 7 days)'
  task cleanup: :environment do
    puts 'Cleaning up expired blocked assets...'
    count = BlockedAsset.cleanup_expired
    puts "✓ Removed #{count} expired blocked asset(s)"
  end

  desc 'List all currently blocked assets'
  task list: :environment do
    blocked = BlockedAsset.active.order(:symbol)

    if blocked.empty?
      puts 'No assets currently blocked.'
    else
      puts "Currently blocked assets (#{blocked.count}):\n\n"
      blocked.each do |asset|
        puts "  #{asset.symbol.ljust(10)} | Reason: #{asset.reason.ljust(20)} | " \
             "Expires in #{asset.days_until_expiration} day(s)"
      end
    end
  end

  desc 'Manually unblock a specific asset'
  task :unblock, [:symbol] => :environment do |_t, args|
    unless args[:symbol]
      puts 'Error: Symbol required. Usage: rake blocked_assets:unblock[PRO]'
      exit 1
    end

    asset = BlockedAsset.find_by(symbol: args[:symbol].upcase)
    if asset
      asset.destroy
      puts "✓ Unblocked #{args[:symbol].upcase}"
    else
      puts "Asset #{args[:symbol].upcase} is not currently blocked"
    end
  end
end
