# frozen_string_literal: true

require 'faraday'

class FecClient
  BASE_URL = 'https://api.open.fec.gov/v1/'

  class FecApiError < StandardError; end

  def initialize(api_key: ENV.fetch('FEC_API_KEY', nil))
    @api_key = api_key
    raise FecApiError, 'FEC_API_KEY not configured' if @api_key.blank?
  end

  def fetch_contributions_by_employer(committee_id:, cycle:, per_page: 100)
    get('schedules/schedule_a/by_employer/', {
          committee_id: committee_id,
          cycle: cycle,
          per_page: per_page,
          sort: '-total'
        })
  end

  def search_candidates(name:, office: nil, state: nil, per_page: 20)
    params = {
      name: name,
      per_page: per_page
    }
    params[:office] = office if office
    params[:state] = state if state

    get('candidates/search/', params)
  end

  def get_candidate_committees(candidate_id)
    get("candidate/#{candidate_id}/committees/")
  end

  private

  attr_reader :api_key

  def get(path, params = {})
    params[:api_key] = api_key

    response = connection.get(path, params)

    raise FecApiError, "FEC API request failed: #{response.status} - #{response.body}" unless response.success?

    JSON.parse(response.body)
  rescue Faraday::Error => e
    raise FecApiError, "FEC API connection error: #{e.message}"
  end

  def connection
    @connection ||= Faraday.new(url: BASE_URL) do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
      f.options.timeout = 30
      f.options.open_timeout = 10
    end
  end
end
