# frozen_string_literal: true

# Command to automatically fetch and populate FEC committee IDs for politicians
class PopulateFecCommitteeIds < GLCommand::Callable
  allows :dry_run, :force_refresh
  returns :stats

  def call
    context.dry_run ||= false
    context.force_refresh ||= false

    client = FecClient.new

    stats = {
      politicians_processed: 0,
      committee_ids_found: 0,
      committee_ids_set: 0,
      skipped: 0,
      failed: 0,
      failures: []
    }

    politicians = if context.force_refresh
                    PoliticianProfile.where.not(state: nil)
                  else
                    PoliticianProfile.where(fec_committee_id: nil).where.not(state: nil)
                  end

    total_without_state = PoliticianProfile.where(state: nil).count
    if total_without_state > 0
      Rails.logger.info("[PopulateFecCommitteeIds] Skipping #{total_without_state} politicians without state data")
    end

    Rails.logger.info("[PopulateFecCommitteeIds] Processing #{politicians.count} politicians...")

    politicians.find_each do |politician|
      stats[:politicians_processed] += 1

      begin
        committee_id = find_committee_id_for_politician(politician, client)

        if committee_id
          stats[:committee_ids_found] += 1

          unless context.dry_run
            politician.update!(fec_committee_id: committee_id)
            stats[:committee_ids_set] += 1
            Rails.logger.info("  ✓ #{politician.name}: #{committee_id}")
          else
            Rails.logger.info("  [DRY RUN] Would set #{politician.name}: #{committee_id}")
          end
        else
          stats[:skipped] += 1
          Rails.logger.debug("  - #{politician.name}: No committee found")
        end

        sleep(0.3) # Rate limiting
      rescue StandardError => e
        stats[:failed] += 1
        stats[:failures] << { name: politician.name, error: e.message }
        Rails.logger.error("  ✗ #{politician.name}: #{e.message}")
      end
    end

    context.stats = stats
    context
  end

  private

  def find_committee_id_for_politician(politician, client)
    # Determine office code (H=House, S=Senate)
    office = determine_office(politician)
    return nil unless office

    # Search for candidate by name
    candidates = search_candidate(politician.name, office, politician.state, client)
    return nil if candidates.empty?

    # Find the best matching candidate
    candidate = find_best_candidate_match(candidates, politician)
    return nil unless candidate

    # Get committees for this candidate
    committees_response = client.get_candidate_committees(candidate['candidate_id'])
    committees = committees_response['results'] || []
    return nil if committees.empty?

    # Find principal campaign committee
    principal_committee = committees.find do |c|
      c['designation'] == 'P' && # Principal campaign committee
        c['committee_type'] == office && # Matches office type
        c['cycles']&.include?(2024) # Active in 2024 cycle
    end

    principal_committee ? principal_committee['committee_id'] : nil
  end

  def determine_office(politician)
    # Use chamber field if available (populated from GitHub data)
    if politician.chamber.present?
      return politician.chamber == 'sen' ? 'S' : 'H'
    end

    # Fall back to checking committee memberships
    if politician.committees.any? { |c| c.name.match?(/senate/i) }
      'S'
    elsif politician.committees.any? { |c| c.name.match?(/house|representative/i) }
      'H'
    else
      # Default to House if unclear (most congress members are in House)
      'H'
    end
  end

  def search_candidate(name, office, state, client)
    # FEC API expects "LAST, FIRST" format
    # Try original name first, then try parsing
    results = []

    # Try direct search
    begin
      response = client.search_candidates(name: name, office: office, state: state)
      results = response.dig('results') || []
    rescue StandardError => e
      Rails.logger.debug("Direct search failed for #{name}: #{e.message}")
    end

    # If no results, try different name formats
    if results.empty? && name.include?(' ')
      parts = name.split
      if parts.length >= 2
        # Try "LAST, FIRST" format
        last_first = "#{parts.last}, #{parts.first}"
        begin
          response = client.search_candidates(name: last_first, office: office, state: state)
          results = response.dig('results') || []
        rescue StandardError => e
          Rails.logger.debug("Last-first search failed for #{name}: #{e.message}")
        end
      end
    end

    results
  end

  def find_best_candidate_match(candidates, politician)
    # If only one result, use it
    return candidates.first if candidates.length == 1

    # Find best match by state and party
    best_match = candidates.find do |c|
      state_match = c['state'] == politician.state
      party_match = normalize_party(c['party']) == normalize_party(politician.party)
      state_match && party_match
    end

    # Fallback to just state match
    best_match || candidates.find { |c| c['state'] == politician.state }
  end

  def normalize_party(party)
    return nil if party.blank?
    
    case party.to_s.upcase
    when 'D', 'DEM', 'DEMOCRAT', 'DEMOCRATIC'
      'D'
    when 'R', 'REP', 'REPUBLICAN'
      'R'
    when 'I', 'IND', 'INDEPENDENT'
      'I'
    else
      party.to_s.first.upcase
    end
  end
end
