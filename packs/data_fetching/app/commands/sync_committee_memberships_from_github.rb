# frozen_string_literal: true

class SyncCommitteeMembershipsFromGithub
  include GLCommand
  
  def call
    client = GitHubLegislatorsClient.new
    
    stats = {
      committees_processed: 0,
      legislators_processed: 0,
      memberships_created: 0,
      politicians_matched: 0,
      politicians_unmatched: []
    }
    
    # Fetch data from GitHub
    Rails.logger.info "Downloading committee data from GitHub..."
    committees_data = client.fetch_committees
    membership_data = client.fetch_committee_memberships
    legislators_data = client.fetch_legislators
    
    # Build bioguide ID to legislator map
    legislators_map = build_legislators_map(legislators_data)
    
    # Process committees
    committees_data.each do |committee_info|
      process_committee(committee_info)
      stats[:committees_processed] += 1
    end
    
    # Process committee memberships
    membership_data.each do |committee_code, members|
      committee = find_committee_by_code(committee_code)
      
      unless committee
        Rails.logger.warn "Committee not found for code: #{committee_code}"
        next
      end
      
      members.each do |member|
        bioguide_id = member["bioguide"]
        legislator = legislators_map[bioguide_id]
        stats[:legislators_processed] += 1
        
        # Try to match to our politician profiles
        politician = match_politician(bioguide_id, legislator)
        
        if politician
          create_membership(politician, committee, member)
          stats[:memberships_created] += 1
          stats[:politicians_matched] += 1
        else
          name = legislator ? legislator["name"]["official_full"] : member["name"]
          stats[:politicians_unmatched] << name unless stats[:politicians_unmatched].include?(name)
        end
      end
    end
    
    # Log results
    Rails.logger.info "Committee sync complete:"
    Rails.logger.info "  Committees: #{stats[:committees_processed]}"
    Rails.logger.info "  Memberships created: #{stats[:memberships_created]}"
    Rails.logger.info "  Politicians matched: #{stats[:politicians_matched]}"
    Rails.logger.info "  Politicians unmatched: #{stats[:politicians_unmatched].count}"
    
    if stats[:politicians_unmatched].any?
      Rails.logger.debug "  Unmatched: #{stats[:politicians_unmatched].join(', ')}"
    end
    
    success(stats)
  end
  
  private
  
  def build_legislators_map(legislators_data)
    legislators_data.each_with_object({}) do |legislator, map|
      bioguide_id = legislator.dig("id", "bioguide")
      map[bioguide_id] = legislator if bioguide_id
    end
  end
  
  def process_committee(committee_info)
    # Map GitHub committee codes to our format
    committee_code = committee_info["thomas_id"] || committee_info["house_committee_id"]
    return unless committee_code
    
    Committee.find_or_create_by(code: committee_code) do |c|
      c.name = committee_info["name"]
      c.chamber = committee_info["type"] # 'house' or 'senate'
      c.url = committee_info["url"]
      c.jurisdiction = committee_info["jurisdiction"]
      c.description = committee_info["jurisdiction"]
      c.display_name = committee_info["name"]
    end
  end
  
  def find_committee_by_code(github_code)
    # GitHub uses codes like "HSBA" (House Committee on Financial Services)
    # Try exact match first
    committee = Committee.find_by(code: github_code)
    return committee if committee
    
    # Try partial matching for subcommittees
    # Format: HSBA13 where HSBA is parent committee, 13 is subcommittee
    if github_code.length > 4
      parent_code = github_code[0..3]
      Committee.find_by(code: parent_code)
    end
  end
  
  def match_politician(bioguide_id, legislator)
    return nil unless legislator
    
    # Try bioguide ID match first
    politician = PoliticianProfile.find_by(bioguide_id: bioguide_id)
    return politician if politician
    
    # Try name matching
    full_name = legislator.dig("name", "official_full")
    return nil unless full_name
    
    # Try exact match
    politician = PoliticianProfile.find_by(name: full_name)
    return politician if politician
    
    # Try "Last, First" to "First Last" conversion
    first = legislator.dig("name", "first")
    last = legislator.dig("name", "last")
    if first && last
      reversed_name = "#{first} #{last}"
      politician = PoliticianProfile.find_by(name: reversed_name)
      return politician if politician
    end
    
    # Try last name only (if unique)
    if last
      candidates = PoliticianProfile.where("name LIKE ?", "%#{last}%")
      return candidates.first if candidates.count == 1
    end
    
    nil
  end
  
  def create_membership(politician, committee, member_info)
    CommitteeMembership.find_or_create_by(
      politician_profile: politician,
      committee: committee
    ) do |m|
      m.role = determine_role(member_info)
      m.is_active = true
      m.joined_at = Date.current # Approximate - GitHub data doesn't have join dates
    end
  end
  
  def determine_role(member_info)
    title = member_info["title"]&.downcase
    
    return "chair" if title&.include?("chair")
    return "ranking_member" if title&.include?("ranking")
    "member"
  end
end
