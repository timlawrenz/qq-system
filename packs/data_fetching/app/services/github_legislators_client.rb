# frozen_string_literal: true

require "yaml"
require "net/http"

class GitHubLegislatorsClient
  BASE_URL = "https://raw.githubusercontent.com/unitedstates/congress-legislators/main"
  
  # Download and parse legislators data
  def fetch_legislators
    yaml_content = download_file("legislators-current.yaml")
    YAML.safe_load(yaml_content, permitted_classes: [Date, Time])
  end
  
  # Download and parse committee membership data
  def fetch_committee_memberships
    yaml_content = download_file("committee-membership-current.yaml")
    YAML.safe_load(yaml_content, permitted_classes: [Date, Time])
  end
  
  # Download and parse committees data
  def fetch_committees
    yaml_content = download_file("committees-current.yaml")
    YAML.safe_load(yaml_content, permitted_classes: [Date, Time])
  end
  
  private
  
  def download_file(filename)
    uri = URI("#{BASE_URL}/#{filename}")
    response = Net::HTTP.get_response(uri)
    
    unless response.is_a?(Net::HTTPSuccess)
      raise "Failed to download #{filename}: #{response.code} #{response.message}"
    end
    
    response.body
  rescue => e
    Rails.logger.error "GitHub download error: #{e.message}"
    raise
  end
end
