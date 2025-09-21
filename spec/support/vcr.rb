# frozen_string_literal: true

require 'vcr'
require 'webmock/rspec'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.default_cassette_options = {
    record: :once,
    match_requests_on: %i[method uri query body]
  }

  # Filter sensitive data - API keys, tokens, etc.
  config.filter_sensitive_data('<QUIVER_API_KEY>') do |interaction|
    auth_header = interaction.request.headers['Authorization']&.first
    auth_header&.gsub('Bearer ', '') if auth_header&.start_with?('Bearer ')
  end

  # Allow real requests for localhost (for Rails server tests)
  config.ignore_localhost = true

  # Allow requests during development/debugging
  config.allow_http_connections_when_no_cassette = false

  # Configure for different environments
  config.default_cassette_options = {
    record: Rails.env.test? ? :once : :new_episodes,
    match_requests_on: %i[method uri query body]
  }
end

# Configure WebMock to work with VCR
WebMock.disable_net_connect!(allow_localhost: true)
