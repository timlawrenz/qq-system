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

# Monkey-patch Alpaca::Trade::Api::Client#bars to support the v2 data API and
# avoid String#map errors when Alpaca returns unexpected payloads.
require 'time'

module Alpaca
  module Trade
    module Api
      class Client
        def bars(timeframe, symbols, limit: 100)
          validate_timeframe(timeframe)

          symbols = Array(symbols).map(&:to_s)

          params = {
            timeframe: timeframe,
            symbols: symbols.join(','),
            limit: limit,
            adjustment: 'raw',
            feed: 'sip'
          }

          response = get_request(data_endpoint, 'v2/stocks/bars', params)
          body = response.body
          json = body.is_a?(String) ? JSON.parse(body) : body

          bars_hash = {}

          if json.is_a?(Hash) && json['bars'].is_a?(Hash)
            # v2 shape: { "bars" => { "SYM" => [ { ... }, ... ] }, "next_page_token" => nil }
            json['bars'].each do |symbol, bars|
              bars_hash[symbol] = Array(bars).filter_map { |bar| build_bar_from_v2_hash(bar, symbol) }
            end
          elsif json.is_a?(Hash)
            # Fallback: original v1-style hash of symbol => [bars]
            json.each do |symbol, bars|
              bars_hash[symbol] = Array(bars).map { |bar| Bar.new(bar) }
            end
          else
            Rails.logger.error("Unexpected Alpaca bars response body: #{body.inspect}")
          end

          bars_hash
        rescue JSON::ParserError => e
          Rails.logger.error("Failed to parse Alpaca bars response: #{e.message}, body=#{body.inspect}")
          {}
        rescue StandardError => e
          Rails.logger.error("Alpaca bars request failed: #{e.message}")
          {}
        end

        private

        # Normalize v2 bar hash (with ISO8601 timestamps) into the shape expected
        # by Alpaca::Trade::Api::Bar (numeric epoch seconds for 't'). Returns nil
        # if the bar is missing required fields so callers can skip it.
        def build_bar_from_v2_hash(bar, symbol)
          return nil unless bar.is_a?(Hash)

          normalized = bar.dup

          return nil if normalized['t'].nil? || normalized['o'].nil? || normalized['h'].nil? ||
                        normalized['l'].nil? || normalized['c'].nil?

          if normalized['t'].is_a?(String)
            normalized['t'] = Time.parse(normalized['t']).to_i
          end

          Bar.new(normalized)
        rescue StandardError => e
          Rails.logger.warn("Skipping invalid Alpaca v2 bar for #{symbol}: #{e.message}, bar=#{bar.inspect}")
          nil
        end
      end
    end
  end
end