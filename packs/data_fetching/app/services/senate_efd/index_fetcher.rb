# frozen_string_literal: true

require 'faraday'
require 'json'

module SenateEfd
  # Queries the DataTables back-end on efdsearch.senate.gov to retrieve the
  # master index of filed Periodic Transaction Reports (PTRs).
  #
  # Uses the session established by SessionManager and pages through results
  # to collect every PTR filed since the provided watermark date.
  #
  # Usage
  #   fetcher = SenateEfd::IndexFetcher.new(session_manager)
  #   reports = fetcher.fetch_ptrs_since(watermark_date) # => [{ first_name:, last_name:, url:, date_received: }, …]
  class IndexFetcher
    BASE_URL = 'https://efdsearch.senate.gov'

    TIMEOUT      = 30
    OPEN_TIMEOUT = 10

    # The DataTables API returns pages of 100 rows by default; we use 100 to
    # keep individual responses small and reduce memory pressure.
    PAGE_SIZE = 100

    # PTR report_type code used by the Senate EFD DataTables back-end.
    REPORT_TYPE_PTR = 11

    attr_reader :api_calls

    def initialize(session_manager)
      @session = session_manager
      @connection = build_connection
      @api_calls = []
    end

    # Fetch all PTR metadata records filed on or after `watermark_date`.
    #
    # @param watermark_date [Date, nil]  only return reports received on/after this date.
    #   Pass nil to fetch everything.
    # @return [Array<Hash>] each hash: :first_name, :last_name, :description,
    #   :url (the /search/view/ptr/{uuid}/ path), :date_received (Date)
    def fetch_ptrs_since(watermark_date = nil)
      reports = []
      start = 0

      loop do
        page = fetch_page(start, watermark_date)
        records = page[:data]
        break if records.empty?

        reports.concat(records)
        break if records.size < PAGE_SIZE # last page

        start += PAGE_SIZE

        # Random jitter between page requests — availability > speed.
        jitter_sleep
      end

      Rails.logger.info("[SenateEfd::IndexFetcher] Fetched #{reports.size} PTR references")
      reports
    end

    private

    def build_connection
      Faraday.new(url: BASE_URL) do |f|
        f.options.timeout      = TIMEOUT
        f.options.open_timeout = OPEN_TIMEOUT
      end
    end

    def fetch_page(start, watermark_date)
      body = build_request_body(start: start, watermark_date: watermark_date)

      response = post_with_retry('/search/report/data/', body)
      raise ApiError, "DataTables API returned #{response.status}" unless response.status == 200

      parsed = JSON.parse(response.body)
      records = parsed['data'].map { |row| parse_row(row) }

      { data: records, total: parsed['recordsTotal'].to_i }
    end

    # The payload the DataTables back-end expects.  `report_types: [11]` limits
    # results to Periodic Transaction Reports (PTRs) only.
    def build_request_body(start:, watermark_date:)
      params = {
        'draw' => '1',
        'start' => start.to_s,
        'length' => PAGE_SIZE.to_s,
        'report_types' => '[11]',
        'filer_types' => '[]',
        'submitted_start_date' => '',
        'submitted_end_date' => '',
        'candidate_state' => '',
        'senator_state' => '',
        'office_id' => '',
        'first_name' => '',
        'last_name' => ''
      }

      params['submitted_start_date'] = watermark_date.strftime('%m/%d/%Y 00:00:00') if watermark_date

      URI.encode_www_form(params)
    end

    def parse_row(row)
      # row is an array from DataTables:
      #   [first_name, last_name, full_name, <a href="...">description</a>, date_received]
      first_name  = row[0].to_s.strip
      last_name   = row[1].to_s.strip
      description = extract_text_from_html(row[3])
      url         = extract_href(row[3])
      date_received = parse_date(row[4])

      {
        first_name: first_name,
        last_name: last_name,
        description: description,
        url: url,
        date_received: date_received
      }
    end

    def extract_text_from_html(html)
      return '' if html.blank?

      # Strip HTML tags — simple regex is sufficient for DataTables anchor cells
      html.gsub(%r{<[^>]+>}, '').strip
    end

    def extract_href(html)
      return '' if html.blank?

      match = html.match(/href="([^"]+)"/)
      match ? match[1] : ''
    end

    def parse_date(str)
      Date.strptime(str.strip, '%m/%d/%Y')
    rescue ArgumentError
      nil
    end

    # ── HTTP with re-auth support ───────────────────────────────────────────

    def post_with_retry(path, body)
      response = post_with_auth(path, body)

      # If the session expired (302 → /search/home/), re-auth and retry once.
      if @session.reauth_required?(response)
        Rails.logger.info('[SenateEfd::IndexFetcher] Session expired — re-authenticating…')
        @session.ensure_authenticated
        response = post_with_auth(path, body)
      end

      response
    end

    def post_with_auth(path, body)
      @session.ensure_authenticated unless @session.authenticated_at

      start_time = Time.current
      response = @connection.post(path) do |req|
        req.headers['Cookie']       = @session.cookie_header
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        req.headers['Referer']      = "#{BASE_URL}/search/"
        req.headers['X-CSRFToken']  = @session.csrf_token_value
        req.body                    = body
      end

      record_api_call(path, response.status, start_time)
      response
    rescue Faraday::Error => e
      record_api_error(path, start_time, e)
      raise ApiError, "Connection error: #{e.message}"
    end

    def record_api_call(path, status, start_time)
      duration = ((Time.current - start_time) * 1000).to_i
      @api_calls << {
        endpoint: "#{BASE_URL}#{path}",
        status_code: status,
        duration_ms: duration,
        timestamp: start_time
      }
    end

    def record_api_error(path, start_time, error)
      duration = ((Time.current - start_time) * 1000).to_i
      @api_calls << {
        endpoint: "#{BASE_URL}#{path}",
        status_code: 0,
        duration_ms: duration,
        timestamp: start_time,
        error: error.message
      }
    end

    # ── Rate limiting / jitter ─────────────────────────────────────────────

    def jitter_sleep
      # Between 1.0 and 3.0 seconds of jitter — availability > speed.
      seconds = 1.0 + (rand * 2.0)
      sleep(seconds)
    end

    class ApiError < StandardError; end
  end
end
