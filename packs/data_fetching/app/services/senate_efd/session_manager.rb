# frozen_string_literal: true

require 'faraday'

module SenateEfd
  # Manages authentication with the Senate EFD portal.
  #
  # Negotiates the click-wrap "I Agree" gate on efdsearch.senate.gov and
  # maintains a valid session.  The session cookie expires after a period of
  # inactivity; this class transparently re-authenticates when it detects a
  # redirect back to the home page (302 → /search/home/).
  #
  # Usage
  #   session = SenateEfd::SessionManager.new
  #   cookies = session.ensure_authenticated   # => "csrftoken=...; sessionid=..."
  #   csrf    = session.csrf_token             # => "abc123..."
  #
  class SessionManager
    BASE_URL = 'https://efdsearch.senate.gov'

    # How long we consider a session "fresh" before re-authing proactively.
    # The actual server-side timeout appears to be ~30 minutes of idle time.
    FRESH_TTL = 10 * 60 # 10 minutes

    TIMEOUT      = 30
    OPEN_TIMEOUT = 10

    attr_reader :csrf_token, :authenticated_at

    def initialize
      @connection = build_connection
      @cookie_jar = {}
      @csrf_token = nil
      @authenticated_at = nil
    end

    # Return a Cookie header string ready to inject into subsequent requests.
    # Re-authenticates if the session is stale or nonexistent.
    def cookie_header
      ensure_authenticated unless fresh?
      @cookie_jar.map { |k, v| "#{k}=#{v}" }.join('; ')
    end

    # Return the CSRF token for the X-CSRFToken header.
    def csrf_token_value
      ensure_authenticated unless fresh?
      @csrf_token.to_s
    end

    # Force a fresh authentication cycle.
    # rubocop:disable Naming/PredicateMethod
    def ensure_authenticated
      Rails.logger.info('[SenateEfd::SessionManager] Authenticating…')
      load_home_page
      post_agreement
      @authenticated_at = Time.current
      Rails.logger.info('[SenateEfd::SessionManager] Authenticated successfully')
      true
    end
    # rubocop:enable Naming/PredicateMethod

    # Did the session lose auth?  Detect by checking if a response redirects
    # back to /search/home/ (the click-wrap gate).
    def reauth_required?(response)
      return false unless response.status == 302

      location = response['location'].to_s
      location.include?('/search/home/')
    end

    private

    def build_connection
      Faraday.new(url: BASE_URL) do |f|
        f.options.timeout      = TIMEOUT
        f.options.open_timeout = OPEN_TIMEOUT
        # Do NOT follow redirects automatically — we need to detect 302 → /search/home/
        # and re-authenticate ourselves.
      end
    end

    def fresh?
      return false if @authenticated_at.nil?
      return false if @csrf_token.blank?
      return false if @cookie_jar.empty?

      (Time.current - @authenticated_at) < FRESH_TTL
    end

    # ── Step 1: GET /search/home/ ────────────────────────────────────────────

    def load_home_page
      response = @connection.get('/search/home/')
      raise AuthError, "GET /search/home/ returned #{response.status}" unless response.status == 200

      extract_cookies(response)
      extract_csrf_token(response.body)
    end

    def extract_cookies(response)
      raw_cookies = response.headers['set-cookie']
      return if raw_cookies.blank?

      # Faraday / WebMock may return a single string or an Array of strings
      cookie_list = raw_cookies.is_a?(Array) ? raw_cookies : [raw_cookies]

      cookie_list.each do |raw|
        next if raw.blank?

        name, rest = raw.split(';', 2).first.split('=', 2)
        @cookie_jar[name] = rest if name.present? && rest
      end
    end

    def extract_csrf_token(body)
      match = body.match(/name="csrfmiddlewaretoken"\s+value="([^"]+)"/)
      raise AuthError, 'Could not extract csrfmiddlewaretoken from home page' unless match

      @csrf_token = match[1]
    end

    # ── Step 2: POST /search/home/ with agreement ────────────────────────────

    def post_agreement
      # Build cookie header directly from jar to avoid recursion through
      # cookie_header → ensure_authenticated → post_agreement → cookie_header.
      cookie_str = @cookie_jar.map { |k, v| "#{k}=#{v}" }.join('; ')

      response = @connection.post('/search/home/') do |req|
        req.headers['Cookie']     = cookie_str
        req.headers['Referer']    = "#{BASE_URL}/search/home/"
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        req.body = URI.encode_www_form(
          'csrfmiddlewaretoken' => @csrf_token,
          'prohibition_agreement' => '1'
        )
      end

      # After successful agreement, the server sets a sessionid cookie and
      # redirects (302) to /search/ — we capture that sessionid.
      extract_cookies(response)

      raise AuthError, 'No sessionid cookie after agreement POST' unless @cookie_jar['sessionid']
    end

    class AuthError < StandardError; end
  end
end
