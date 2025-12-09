# frozen_string_literal: true

require "yaml"
require "net/http"

class SyncCommitteeMembershipsFromGithub < GLCommand::Callable
  returns :committees_processed, :memberships_created, :politicians_matched, :politicians_unmatched
  
  BASE_URL = "https://raw.githubusercontent.com/unitedstates/congress-legislators/main"
  
  def call
    # Fetch data from GitHub
    Rails.logger.info "Downloading committee data from GitHub..."
    committees_data = fetch_yaml("committees-current.yaml")
    membership_data = fetch_yaml("committee-membership-current.yaml")
    legislators_data = fetch_yaml("legislators-current.yaml")
    
    # Build bioguide ID to legislator map
    legislators_map = build_legislators_map(legislators_data)
    
    # Initialize counters
    committees_count = 0
    legislators_count = 0
    memberships_count = 0
    matched_count = 0
    unmatched_list = []
    
    # Process committees
    committees_data.each do |committee_info|
      process_committee(committee_info)
      committees_count += 1
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
        legislators_count += 1
        
        # Try to match to our politician profiles
        politician = match_politician(bioguide_id, legislator)
        
        if politician
          create_membership(politician, committee, member)
          memberships_count += 1
          matched_count += 1
        else
          name = legislator ? legislator["name"]["official_full"] : member["name"]
          unmatched_list << name unless unmatched_list.include?(name)
        end
      end
    end
    
    # Set return values on context
    context.committees_processed = committees_count
    context.memberships_created = memberships_count
    context.politicians_matched = matched_count
    context.politicians_unmatched = unmatched_list
    
    # Log results
    Rails.logger.info "Committee sync complete:"
    Rails.logger.info "  Committees: #{committees_count}"
    Rails.logger.info "  Memberships created: #{memberships_count}"
    Rails.logger.info "  Politicians matched: #{matched_count}"
    Rails.logger.info "  Politicians unmatched: #{unmatched_list.count}"
    
    if unmatched_list.any?
      Rails.logger.debug "  Unmatched: #{unmatched_list.join(', ')}"
    end
  end
  
  private
  
  def fetch_yaml(filename)
    uri = URI("#{BASE_URL}/#{filename}")
    response = Net::HTTP.get_response(uri)
    
    unless response.is_a?(Net::HTTPSuccess)
      raise "Failed to download #{filename}: #{response.code} #{response.message}"
    end
    
    YAML.safe_load(response.body, permitted_classes: [Date, Time])
  rescue => e
    Rails.logger.error "GitHub download error: #{e.message}"
    raise
  end
  
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
      m.start_date = Date.current # GitHub data doesn't have exact dates
    end
  end
  
  def determine_role(member_info)
    # Not used anymore - no role column
    title = member_info["title"]&.downcase
    
    return "chair" if title&.include?("chair")
    return "ranking_member" if title&.include?("ranking")
    "member"
  end
end
