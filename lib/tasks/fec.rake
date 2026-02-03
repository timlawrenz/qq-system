# frozen_string_literal: true

namespace :fec do
  desc 'Automatically populate FEC committee IDs for politicians'
  task populate_committee_ids: :environment do
    puts '[fec:populate_committee_ids] Starting automatic FEC committee ID lookup...'
    puts ''

    result = PopulateFecCommitteeIds.call(dry_run: false)

    if result.success?
      stats = result.stats
      puts "\n[fec:populate_committee_ids] ✓ Complete"
      puts "  Politicians processed: #{stats[:politicians_processed]}"
      puts "  Committee IDs found: #{stats[:committee_ids_found]}"
      puts "  Committee IDs set: #{stats[:committee_ids_set]}"
      puts "  Skipped (no match): #{stats[:skipped]}"
      puts "  Failed: #{stats[:failed]}"

      if stats[:failures].any?
        puts "\n  Failures:"
        stats[:failures].each do |failure|
          puts "    - #{failure[:name]}: #{failure[:error]}"
        end
      end
    else
      puts "\n[fec:populate_committee_ids] ✗ ERROR: #{result.error}"
      exit 1
    end

    puts '[fec:populate_committee_ids] Done.'
  end

  desc 'Dry run: Show what committee IDs would be populated'
  task populate_committee_ids_dry_run: :environment do
    puts '[fec:populate_committee_ids] DRY RUN - No changes will be made'
    puts ''

    result = PopulateFecCommitteeIds.call(dry_run: true)

    if result.success?
      stats = result.stats
      puts "\n[fec:populate_committee_ids] ✓ Complete (DRY RUN)"
      puts "  Politicians that would be processed: #{stats[:politicians_processed]}"
      puts "  Committee IDs that would be found: #{stats[:committee_ids_found]}"
      puts "  Politicians that would be updated: #{stats[:committee_ids_set]}"
      puts "  Would skip (no match): #{stats[:skipped]}"

      if stats[:failed].positive?
        puts "\n  Would fail:"
        stats[:failures].each do |failure|
          puts "    - #{failure[:name]}: #{failure[:error]}"
        end
      end

      puts "\nRun without dry_run to apply changes:"
      puts "  rake fec:populate_committee_ids"
    else
      puts "\n[fec:populate_committee_ids] ✗ ERROR: #{result.error}"
      exit 1
    end
  end

  desc 'Sync FEC campaign contributions for politicians with committee IDs'
  task sync: :environment do
    puts '[fec:sync] Starting FEC contribution sync...'

    result = SyncFecContributions.call(cycle: 2024)

    if result.success?
      stats = result.stats
      total = stats[:classified_amount] + stats[:unclassified_amount]
      classified_pct = total.positive? ? (stats[:classified_amount] / total * 100).round(1) : 0

      puts '[fec:sync] ✓ Sync complete'
      puts "  Politicians processed: #{stats[:politicians_processed]}"
      puts "  Contributions created: #{stats[:contributions_created]}"
      puts "  Contributions updated: #{stats[:contributions_updated]}"
      puts "  Total contributions: $#{total.round(0)}"
      puts "  Classification rate: #{classified_pct}%"

      puts '  ⚠️  WARNING: Classification rate below 65% threshold' if classified_pct < 65 && total > 10_000

      if stats[:unclassified_employers].any?
        puts "\n  Top unclassified employers (>$10k):"
        stats[:unclassified_employers].take(10).each do |emp|
          puts "    - #{emp[:name]}: $#{emp[:amount].round(0)}"
        end
      end
    else
      puts "[fec:sync] ✗ ERROR: #{result.error}"
      exit 1
    end

    puts '[fec:sync] Done.'
  end

  desc 'Sync FEC data for a single politician by ID'
  task :sync_politician, [:politician_id] => :environment do |_t, args|
    unless args[:politician_id]
      puts 'Usage: rake fec:sync_politician[politician_id]'
      exit 1
    end

    politician = PoliticianProfile.find(args[:politician_id])
    puts "[fec:sync_politician] Syncing FEC data for: #{politician.name}"

    unless politician.fec_committee_id
      puts '  ✗ ERROR: Politician has no fec_committee_id set'
      exit 1
    end

    result = SyncFecContributions.call(
      politician_id: politician.id,
      cycle: 2024,
      force_refresh: true
    )

    if result.success?
      stats = result.stats
      total = stats[:classified_amount] + stats[:unclassified_amount]
      classified_pct = total.positive? ? (stats[:classified_amount] / total * 100).round(1) : 0

      puts '  ✓ Sync complete'
      puts "  Total contributions: $#{total.round(0)}"
      puts "  Classification rate: #{classified_pct}%"
      puts "  Contributions created: #{stats[:contributions_created]}"
      puts "  Contributions updated: #{stats[:contributions_updated]}"
    else
      puts "  ✗ ERROR: #{result.error}"
      exit 1
    end

    puts '[fec:sync_politician] Done.'
  end

  desc 'Set FEC committee ID for a politician'
  task :set_committee_id, %i[name committee_id] => :environment do |_t, args|
    unless args[:name] && args[:committee_id]
      puts 'Usage: rake fec:set_committee_id["Nancy Pelosi","C00268623"]'
      exit 1
    end

    politician = PoliticianProfile.find_by('name ILIKE ?', args[:name])
    unless politician
      puts "  ✗ ERROR: Politician not found: #{args[:name]}"
      exit 1
    end

    politician.update!(fec_committee_id: args[:committee_id])
    puts "  ✓ Set FEC committee ID for #{politician.name}: #{args[:committee_id]}"
  end

  desc 'List politicians with FEC committee IDs'
  task list_committees: :environment do
    politicians = PoliticianProfile.where.not(fec_committee_id: nil)

    if politicians.empty?
      puts 'No politicians have FEC committee IDs set.'
    else
      puts "Politicians with FEC committee IDs (#{politicians.count}):"
      politicians.order(:name).each do |p|
        puts "  #{p.name} (#{p.party}-#{p.state}): #{p.fec_committee_id}"
      end
    end
  end

  desc 'Show FEC contribution stats'
  task stats: :environment do
    total_contributions = PoliticianIndustryContribution.current_cycle.count
    total_politicians = PoliticianProfile.where.not(fec_committee_id: nil).count
    politicians_with_data = PoliticianIndustryContribution.current_cycle.distinct.count(:politician_profile_id)

    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts '💰 FEC Contribution Statistics (2024 Cycle)'
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

    puts "Politicians with committee IDs: #{total_politicians}"
    puts "Politicians with FEC data: #{politicians_with_data}"
    puts "Total contribution records: #{total_contributions}"

    if total_contributions.positive?
      significant = PoliticianIndustryContribution.current_cycle.significant.count
      puts "Significant contributions (>$10k): #{significant}"

      total_amount = PoliticianIndustryContribution.current_cycle.sum(:total_amount)
      puts "Total contribution amount: $#{total_amount.round(0)}"

      puts "\nTop industries by contribution amount:"
      Industry.joins(:politician_industry_contributions)
              .where(politician_industry_contributions: { cycle: 2024 })
              .select('industries.name, SUM(politician_industry_contributions.total_amount) as total')
              .group('industries.name')
              .order(total: :desc)
              .limit(10)
              .each do |industry|
        puts "  #{industry.name}: $#{industry.total.to_f.round(0)}"
      end

      puts "\nTop politicians by contribution amount:"
      PoliticianProfile.joins(:politician_industry_contributions)
                       .where(politician_industry_contributions: { cycle: 2024 })
                       .select('politician_profiles.name, SUM(politician_industry_contributions.total_amount) as total')
                       .group('politician_profiles.name')
                       .order(total: :desc)
                       .limit(10)
                       .each do |pol|
        puts "  #{pol.name}: $#{pol.total.to_f.round(0)}"
      end
    end

    puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  end
end
