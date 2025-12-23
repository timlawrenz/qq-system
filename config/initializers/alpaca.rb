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

  prefix = alpaca_env == :live ? 'ALPACA_LIVE' : 'ALPACA_PAPER'

  key_id = ENV["#{prefix}_API_KEY_ID"]
  key_secret = ENV["#{prefix}_API_SECRET_KEY"]

  # Default trade API endpoint if not overridden
  default_endpoint = alpaca_env == :live ? 'https://api.alpaca.markets' : 'https://paper-api.alpaca.markets'
  endpoint = ENV["#{prefix}_BASE_URL"] || default_endpoint

  unless key_id.present? && key_secret.present?
    raise StandardError, "Missing Alpaca API credentials for environment: #{alpaca_env} (expected #{prefix}_API_KEY_ID / #{prefix}_API_SECRET_KEY)"
  end

  # Configure Alpaca Trade API
  Alpaca::Trade::Api.configure do |config|
    config.key_id = key_id
    config.key_secret = key_secret
    config.endpoint = endpoint
  end

  Rails.logger.info("Alpaca::Trade::Api configured for environment: #{alpaca_env}, endpoint=#{endpoint}")
end

# Monkey-patch Alpaca::Trade::Api::Client#bars to support the v2 data API and
# avoid String#map errors when Alpaca returns unexpected payloads.
require 'time'

module Alpaca
  module Trade
    module Api
      class Client
        def bars(timeframe, symbols, limit: 100, start_time: nil, end_time: nil)
          validate_timeframe(timeframe)

          symbols = Array(symbols).map(&:to_s)

          params = {
            timeframe: timeframe,
            symbols: symbols.join(','),
            limit: limit,
            adjustment: 'raw',
            feed: 'iex' # Use IEX feed to match subscription tier
          }

          params[:start] = start_time if start_time
          params[:end] = end_time if end_time

          attempts = 0

          begin
            response = get_request(data_endpoint, 'v2/stocks/bars', params)

            if response.respond_to?(:status) && response.status.to_i == 429
              reset_header = response.headers['X-RateLimit-Reset'] || response.headers['x-ratelimit-reset']

              if reset_header
                reset_time = reset_header.to_i
                sleep_duration = reset_time - Time.now.to_i
                if sleep_duration.positive?
                  Rails.logger.warn(
                    "Alpaca bars request hit rate limit. Sleeping for #{sleep_duration} seconds " \
                    "until #{Time.at(reset_time)}."
                  )
                  sleep(sleep_duration)
                end
              else
                Rails.logger.warn('Alpaca bars request hit rate limit without reset header; sleeping for 1 second')
                sleep(1)
              end

              attempts += 1

              # On rate limit, try the request one more time after sleeping.
              if attempts < 2
                response = get_request(data_endpoint, 'v2/stocks/bars', params)
              end
            end

            body = response.body
            json = body.is_a?(String) ? JSON.parse(body) : body

            bars_hash = {}

            if json.is_a?(Hash) && json['message'].present?
              Rails.logger.warn("Alpaca bars request returned error payload: #{json['message']}")
            elsif json.is_a?(Hash) && json['bars'].is_a?(Hash)
              # v2 shape: { "bars" => { "SYM" => [ { ... }, ... ] }, "next_page_token" => nil }
              json['bars'].each do |symbol, bars|
                bars_hash[symbol] = Array(bars).filter_map { |bar| build_bar_from_v2_hash(bar, symbol) }
              end
            elsif json.is_a?(Hash)
              # Fallback: original v1-style hash of symbol => [bars]
              json.each do |symbol, bars|
                next if symbol.to_s == 'next_page_token'

                bars_hash[symbol] = Array(bars).filter_map do |bar|
                  next unless bar.is_a?(Hash)

                  Bar.new(bar)
                end
              end
            else
              Rails.logger.error("Unexpected Alpaca bars response body: #{body.inspect}")
            end

            bars_hash
          rescue JSON::ParserError => e
            # If JSON parsing fails (often because Alpaca returned an HTML error page),
            # issue a direct debug request so we can log the actual status and body.
            begin
              debug_conn = Faraday.new(url: data_endpoint)
              debug_response = debug_conn.get('v2/stocks/bars') do |req|
                params.each { |k, v| req.params[k.to_s] = v }
                req.headers['APCA-API-KEY-ID'] = key_id
                req.headers['APCA-API-SECRET-KEY'] = key_secret
              end

              body = debug_response.body
              body_snippet = body.is_a?(String) ? body[0, 500] : body.inspect

              Rails.logger.error(
                "Failed to parse Alpaca bars response: #{e.message}, " \
                "status=#{debug_response.status}, body_snippet=#{body_snippet.inspect}"
              )
            rescue StandardError => debug_error
              Rails.logger.error(
                "Failed to debug Alpaca bars response after JSON parse error: #{debug_error.message}"
              )
            end

            {}
          rescue StandardError => e
            body_snippet = if defined?(body) && body.is_a?(String)
                             body[0, 500]
                           else
                             defined?(body) ? body.inspect : 'nil'
                           end
            Rails.logger.error(
              "Alpaca bars request failed: #{e.message}, body_snippet=#{body_snippet.inspect}"
            )
            {}
          end
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