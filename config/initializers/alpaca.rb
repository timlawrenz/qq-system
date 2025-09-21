# frozen_string_literal: true

# Alpaca API Configuration
#
# Configure the Alpaca Trading API client with credentials from Rails credentials or environment variables.
# The configuration uses the same credential resolution strategy as the existing AlpacaApiClient service.

require 'alpaca/trade/api'

# Helper function to fetch credentials using the same strategy as AlpacaApiClient
def fetch_alpaca_credential(env_var, default_value)
  # Try environment variable first
  env_value = ENV.fetch(env_var, nil)
  return env_value if env_value.present?

  # Try Rails credentials second
  credentials_value = Rails.application.credentials.dig(:alpaca, env_var.downcase.to_sym)
  return credentials_value if credentials_value.present?

  # Use default for development/test
  if Rails.env.local?
    Rails.logger.warn("Using default #{env_var} for #{Rails.env} environment") if defined?(Rails)
    return default_value
  end

  # Fail in production without real credentials
  raise StandardError, "Missing required Alpaca credential: #{env_var}"
end

# Configure Alpaca Trade API
Alpaca::Trade::Api.configure do |config|
  # Use the same credential resolution logic as AlpacaApiClient
  config.key_id = fetch_alpaca_credential('ALPACA_API_KEY', 'test-api-key')
  config.key_secret = fetch_alpaca_credential('ALPACA_SECRET_KEY', 'test-secret-key')
  
  # API endpoint configuration - use paper trading for development/test
  config.endpoint = if defined?(Rails) && Rails.env.production?
                      'https://api.alpaca.markets'
                    else
                      'https://paper-api.alpaca.markets'
                    end
end