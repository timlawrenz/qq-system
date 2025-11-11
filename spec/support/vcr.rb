# frozen_string_literal: true

require 'vcr'
require 'webmock/rspec'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Always record new episodes to capture latest API responses
  config.default_cassette_options = {
    record: :new_episodes, # Record new interactions, replay existing ones
    match_requests_on: %i[method uri] # Match on method and URI (not body/query for flexibility)
  }

  # Filter sensitive data - API keys, tokens, etc.
  config.filter_sensitive_data('<QUIVER_API_KEY>') do |interaction|
    auth_header = interaction.request.headers['Authorization']&.first
    auth_header&.gsub('Bearer ', '') if auth_header&.start_with?('Bearer ')
  end

  # Filter Alpaca API credentials
  config.filter_sensitive_data('<ALPACA_API_KEY>') do |interaction|
    interaction.request.headers['Apca-Api-Key-Id']&.first
  end

  config.filter_sensitive_data('<ALPACA_SECRET_KEY>') do |interaction|
    interaction.request.headers['Apca-Api-Secret-Key']&.first
  end

  # Allow real requests for localhost (for Rails server tests)
  config.ignore_localhost = true

  # Allow real HTTP connections when no cassette exists (for recording)
  config.allow_http_connections_when_no_cassette = true
end

# Configure WebMock - allow real connections except when VCR has a cassette
WebMock.allow_net_connect!
