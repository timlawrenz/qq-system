# frozen_string_literal: true

# Alpaca API Configuration
#
# Configure the Alpaca Trading API client with credentials from Rails credentials.
# This initializer uses the same environment-based configuration as the AlpacaApiClient.

require 'alpaca/trade/api'

Rails.application.config.after_initialize do
  # Determine the environment (:paper or :live)
  # Default to :paper for all non-production environments
  alpaca_env = defined?(Rails) && Rails.env.production? ? :live : :paper

  # Fetch the entire configuration hash for the environment
  config_hash = Rails.application.credentials.dig(:alpaca, alpaca_env)

  # Raise a clear error if the configuration is missing or incomplete
  unless config_hash && config_hash[:base_url] && config_hash[:alpaca_api_key] && config_hash[:alpaca_api_secret]
    raise StandardError, "Missing or incomplete Alpaca configuration for environment: #{alpaca_env}"
  end

  # Configure Alpaca Trade API
  Alpaca::Trade::Api.configure do |config|
    config.key_id = config_hash[:alpaca_api_key]
    config.key_secret = config_hash[:alpaca_api_secret]
    config.endpoint = config_hash[:base_url]
  end

  Rails.logger.info("Alpaca::Trade::Api configured for environment: #{alpaca_env}")
end