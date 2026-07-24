# frozen_string_literal: true

require 'faraday'
require 'nokogiri'

module SenateEfd
  # Fetches and parses a single Periodic Transaction Report (PTR) HTML page
  # from the Senate EFD portal.
  #
  # Each PTR lists individual stock transactions in a <table class="table-striped">.
  # The parser extracts each row and normalizes it to the standard trade hash
  # format used throughout the qq-system.
  #
  # Usage
  #   parser = SenateEfd::ReportParser.new(session_manager)
  #   trades = parser.parse_report('/search/view/ptr/abc-123/')
  #   # => [{ ticker:, company:, transaction_date:, transaction_type:,
  #   #       trade_size_usd:, asset_type: }, …]
  # rubocop:disable Metrics/MethodLength
  class ReportParser
    BASE_URL = 'https://efdsearch.senate.gov'

    TIMEOUT      = 30
    OPEN_TIMEOUT = 10

    attr_reader :api_calls

    def initialize(session_manager)
      @session = session_manager
      @connection = build_connection
      @api_calls = []
    end

    # Fetch and parse a single PTR page.
    #
    # @param report_path [String]  the URL path, e.g. "/search/view/ptr/<uuid>/"
    # @param report_meta [Hash]    metadata from IndexFetcher for logging context
    #   (first_name:, last_name:, date_received:)
    # @return [Array<Hash>] normalized trade hashes
    def parse_report(report_path, report_meta = {})
      html = fetch_report_page(report_path)
      return [] if html.blank?

      trades = extract_trades_from_html(html, report_path, report_meta)
      Rails.logger.debug do
        "[SenateEfd::ReportParser] #{report_path}: extracted #{trades.size} trades"
      end
      trades
    end

    private

    def build_connection
      Faraday.new(url: BASE_URL) do |f|
        f.options.timeout      = TIMEOUT
        f.options.open_timeout = OPEN_TIMEOUT
      end
    end

    def fetch_report_page(report_path)
      response = get_with_retry(report_path)
      return nil unless response.status == 200

      response.body
    end

    def get_with_retry(path)
      response = get_with_auth(path)

      if @session.reauth_required?(response)
        Rails.logger.info('[SenateEfd::ReportParser] Session expired — re-authenticating…')
        @session.ensure_authenticated
        response = get_with_auth(path)
      end

      response
    end

    def get_with_auth(path)
      start_time = Time.current
      response = @connection.get(path) do |req|
        req.headers['Cookie']  = @session.cookie_header
        req.headers['Referer'] = "#{BASE_URL}/search/"
      end

      duration = ((Time.current - start_time) * 1000).to_i
      @api_calls << {
        endpoint: "#{BASE_URL}#{path}",
        status_code: response.status,
        duration_ms: duration,
        timestamp: start_time
      }

      response
    rescue Faraday::Error => e
      duration = ((Time.current - start_time) * 1000).to_i
      @api_calls << {
        endpoint: "#{BASE_URL}#{path}",
        status_code: 0,
        duration_ms: duration,
        timestamp: start_time,
        error: e.message
      }
      Rails.logger.warn("[SenateEfd::ReportParser] Connection error for #{path}: #{e.message}")
      nil
    end

    # ── HTML Parsing ───────────────────────────────────────────────────────

    def extract_trades_from_html(html, report_path, report_meta)
      doc = Nokogiri::HTML(html)

      # Skip PDF-based filings — can't parse without OCR
      if pdf_filing?(doc, html)
        Rails.logger.info("[SenateEfd::ReportParser] Skipping PDF filing: #{report_path}")
        return []
      end

      # Find the transaction table
      table = find_transaction_table(doc)
      return [] unless table

      rows = table.css('tbody tr')
      rows.filter_map do |row|
        parse_transaction_row(row, report_meta)
      end
    end

    def pdf_filing?(doc, html)
      # Check for a "PDF Disclosed Filing" message or a direct PDF link
      return true if html.include?('PDF Disclosed Filing')
      return true if doc.text.include?('PDF Disclosed Filing')

      false
    end

    # Locate the stock transactions table.
    # The design doc specifies `table.table-striped` — try that first,
    # then fall back to any table with the expected column headers.
    def find_transaction_table(doc)
      table = doc.at_css('table.table-striped')
      return table if table

      # Fallback: find a table whose header row mentions ticker/transaction terms
      doc.css('table').find do |t|
        header_text = t.css('th').map(&:text).join(' ').downcase
        header_text.include?('ticker') ||
          header_text.include?('transaction date') ||
          header_text.include?('asset')
      end
    end

    # Parse a single <tr> into a normalized trade hash.
    # Returns nil if the row does not represent a stock trade.
    def parse_transaction_row(row, report_meta)
      cells = row.css('td')
      return nil if cells.size < 3

      # Extract column data — the column order varies across different
      # versions of the PTR form, so we use header-based mapping.
      ticker = extract_ticker(row, cells)
      return nil if ticker.blank? || ticker == '--'

      asset_description = extract_asset_description(row, cells)
      transaction_date = extract_transaction_date(row, cells)
      return nil if transaction_date.nil?

      transaction_type = extract_transaction_type(row, cells)
      return nil if transaction_type.nil?

      amount_range = extract_amount_range(row, cells)

      {
        ticker: ticker,
        company: asset_description,
        trader_name: format_trader_name(report_meta),
        trader_source: 'congress',
        transaction_date: transaction_date,
        transaction_type: transaction_type,
        trade_size_usd: amount_range,
        disclosed_at: report_meta[:date_received]&.to_datetime
      }
    end

    # ── Field Extractors ───────────────────────────────────────────────────

    # Find the ticker column by scanning cells for text that looks like a ticker
    # (1-5 uppercase letters) or searching for a header named "Ticker"/"Symbol".
    def extract_ticker(_row, cells)
      cells.each do |cell|
        text = cell.text.strip
        # Tickers are 1-5 uppercase letters
        return text if text.match?(/\A[A-Z]{1,5}\z/)
      end
      nil
    end

    def extract_asset_description(_row, cells)
      # Usually the cell adjacent to the ticker, or the cell with the longest text
      descriptions = cells.reject { |c| c.text.strip.match?(/\A[A-Z]{1,5}\z/) }
                          .reject { |c| c.text.strip.match?(/\A\$[\d,]+/) }
                          .reject { |c| c.text.strip.match?(/\A\d{1,2}\/\d{1,2}\/\d{4}\z/) }

      descriptions.map { |c| c.text.strip }.max_by(&:length) || ''
    end

    def extract_transaction_date(_row, cells)
      cells.each do |cell|
        text = cell.text.strip
        # MM/DD/YYYY format
        return Date.strptime(text, '%m/%d/%Y') if text.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z})
      end
      nil
    end

    def extract_transaction_type(_row, cells)
      # Nokogiri .text concatenates cell contents without separators,
      # so "AAPL" + "Purchase" becomes "AAPLPurchase". Join with spaces.
      row_text = cells.map { |c| c.text.strip }.join(' ').downcase

      return 'Purchase' if row_text.match?(/\bpurchase\b|\bbuy\b|\bacquir/i)
      return 'Sale'     if row_text.match?(/\bsale\b|\bsell\b|\bsold\b|\bdispos/i)

      nil
    end

    def extract_amount_range(_row, cells)
      cells.each do |cell|
        text = cell.text.strip
        # Amount ranges look like: $1,001 - $15,000  or  $50,001 - $100,000
        return text if text.match?(/\A\$\d[\d,]+/i)
      end
      nil
    end

    def format_trader_name(report_meta)
      last  = report_meta[:last_name]  || ''
      first = report_meta[:first_name] || ''

      # Senate format: "Last, First" — matching the existing convention
      "#{last}, #{first}".strip.delete_prefix(', ')
    end
  end
end
# rubocop:enable Metrics/MethodLength
