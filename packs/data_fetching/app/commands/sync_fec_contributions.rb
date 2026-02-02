# frozen_string_literal: true

# rubocop:disable Metrics/MethodLength
class SyncFecContributions < GLCommand::Callable
  allows :cycle, :force_refresh, :politician_id
  returns :stats

  def call
    context.cycle ||= 2024
    client = FecClient.new

    stats = {
      politicians_processed: 0,
      contributions_created: 0,
      contributions_updated: 0,
      classified_amount: 0.0,
      unclassified_amount: 0.0,
      unclassified_employers: []
    }

    politicians = if context.politician_id
                    PoliticianProfile.where(id: context.politician_id)
                  else
                    PoliticianProfile.where.not(fec_committee_id: nil)
                  end

    politicians.find_each do |politician|
      next if skip_recent_sync?(politician) && !context.force_refresh

      sync_politician_contributions(politician, client, stats)
      stats[:politicians_processed] += 1

      sleep(0.5) unless context.politician_id # Rate limiting (skip for single politician)
    end

    log_results(stats)
    context.stats = stats
    context
  rescue FecClient::FecApiError => e
    Rails.logger.error("[SyncFecContributions] FEC API error: #{e.message}")
    stats[:error] = e.message
    context.stats = stats
    context
  end

  private

  def sync_politician_contributions(politician, client, stats)
    Rails.logger.info "Syncing FEC contributions for #{politician.name}..."

    response = client.fetch_contributions_by_employer(
      committee_id: politician.fec_committee_id,
      cycle: context.cycle,
      per_page: 100
    )

    results = response['results'] || []

    # Group contributions by industry
    industry_contributions = Hash.new { |h, k| h[k] = { employers: [], total: 0, count: 0 } }

    results.each do |employer_data|
      employer = employer_data['employer']
      amount = employer_data['total'].to_f
      count = employer_data['count'].to_i

      next if skip_employer?(employer, amount)

      industry = Industry.classify_employer(employer)

      if industry
        industry_contributions[industry][:employers] << { name: employer, amount: amount, count: count }
        industry_contributions[industry][:total] += amount
        industry_contributions[industry][:count] += count
        stats[:classified_amount] += amount
      else
        track_unclassified(employer, amount, stats)
        stats[:unclassified_amount] += amount
      end
    end

    # Store aggregated contributions
    industry_contributions.each do |industry, data|
      store_contribution(politician, industry, data, stats)
    end
  end

  def skip_employer?(employer, amount)
    return true if amount < 1_000

    # Skip non-industry employers
    employer.match?(/RETIRED|NOT EMPLOYED|SELF|N\/A|NONE|HOMEMAKER|INFORMATION REQUESTED/i)
  end

  def store_contribution(politician, industry, data, stats)
    contribution = PoliticianIndustryContribution.find_or_initialize_by(
      politician_profile: politician,
      industry: industry,
      cycle: context.cycle
    )

    was_new = contribution.new_record?

    contribution.total_amount = data[:total]
    contribution.contribution_count = data[:count]
    contribution.employer_count = data[:employers].count

    # Store top 10 employers by amount
    contribution.top_employers = data[:employers]
                                 .sort_by { |e| -e[:amount] }
                                 .take(10)
                                 .map { |e| { 'name' => e[:name], 'amount' => e[:amount], 'count' => e[:count] } }

    contribution.fetched_at = Time.current

    return unless contribution.save

    if was_new
      stats[:contributions_created] += 1
    else
      stats[:contributions_updated] += 1
    end
  end

  def track_unclassified(employer, amount, stats)
    return unless amount >= 10_000 # Only track significant unclassified

    stats[:unclassified_employers] << { name: employer, amount: amount }
  end

  def skip_recent_sync?(politician)
    PoliticianIndustryContribution
      .where(politician_profile: politician, cycle: context.cycle)
      .exists?(['fetched_at > ?', 30.days.ago])
  end

  def log_results(stats)
    total = stats[:classified_amount] + stats[:unclassified_amount]
    classified_pct = total.positive? ? (stats[:classified_amount] / total * 100).round(1) : 0

    Rails.logger.info 'FEC Sync Complete:'
    Rails.logger.info "  Politicians: #{stats[:politicians_processed]}"
    Rails.logger.info "  Contributions created: #{stats[:contributions_created]}"
    Rails.logger.info "  Contributions updated: #{stats[:contributions_updated]}"
    Rails.logger.info "  Classified: #{classified_pct}% of $#{total.round(0)}"

    return unless stats[:unclassified_employers].any?

    top_unclassified = stats[:unclassified_employers]
                       .sort_by { |e| -e[:amount] }
                       .take(20)
    Rails.logger.warn "  Unclassified employers (>$10k): #{top_unclassified.inspect}"
  end
end
# rubocop:enable Metrics/MethodLength
