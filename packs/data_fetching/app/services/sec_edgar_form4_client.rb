# frozen_string_literal: true

require 'faraday'
require 'nokogiri'
require 'zlib'

# SecEdgarForm4Client
#
# Fetches corporate insider trades directly from SEC EDGAR Form 4 filings.
# Form 4 is filed within 2 business days whenever a director, officer, or
# 10%+ shareholder trades the company's securities.
#
# Primary endpoints:
#   Quarterly index: https://www.sec.gov/Archives/edgar/full-index/YYYY/QTRN/form.gz
#   Filing XML:      https://www.sec.gov/Archives/edgar/data/{cik}/{accession}/form4.xml
#   Documentation:   https://www.sec.gov/dera/data/insider-trading
#
# Authentication: None. The SEC requires a descriptive User-Agent header.
#   Set SEC_EDGAR_USER_AGENT in your environment:
#   "YourAppName contact@yourdomain.com"
#
# Rate limit: 10 requests/second per SEC policy.
#   See: https://www.sec.gov/os/accessing-edgar-data
#
# Returns data in the same format as the former QuiverClient#fetch_insider_trades so that
# no downstream code (FetchInsiderTrades, trading strategies) requires changes.
#
# rubocop:disable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
class SecEdgarForm4Client
  EDGAR_FILING_BASE = 'https://www.sec.gov'

  # SEC requires: "AppName contact@domain.com" — customize via env var
  USER_AGENT = ENV.fetch('SEC_EDGAR_USER_AGENT', 'qq-trading-system trading-ops@qq-system.example.com')

  # Stay comfortably under the 10 req/sec SEC limit
  REQUEST_INTERVAL = 0.15

  # Cap filings per run to keep execution time predictable.
  # At ~200 Form 4 filings/day, a 7-day lookback = ~1400 filings.
  # Capping ensures the daily job completes in under 5 minutes.
  MAX_FILINGS = 500

  attr_reader :api_calls

  def initialize
    @api_calls = []
    @last_request_at = nil
    @filing_connection = build_filing_connection
  end

  # Fetch insider trades from SEC Form 4 filings filed within the date range.
  #
  # @param options [Hash]
  #   :start_date [Date]    filing date range start (default: 14 days ago)
  #   :end_date   [Date]    filing date range end   (default: today)
  #   :limit      [Integer] max trades to return    (default: 1000)
  #
  # @return [Array<Hash>] trade hashes matching the former QuiverClient output:
  #   :ticker, :company, :trader_name, :trader_source (:insider),
  #   :transaction_date, :transaction_type, :trade_size_usd, :disclosed_at,
  #   :relationship, :shares_held, :ownership_percent
  def fetch_insider_trades(options = {})
    start_date = options[:start_date] || 14.days.ago.to_date
    end_date   = options[:end_date]   || Date.current
    limit      = options[:limit] || 1000

    Rails.logger.info(
      "SecEdgarForm4Client: Fetching Form 4 filings #{start_date}..#{end_date} " \
      "(max #{MAX_FILINGS} filings, limit #{limit} trades)"
    )

    filings = collect_form4_filing_refs(start_date, end_date)
    Rails.logger.info("SecEdgarForm4Client: #{filings.size} Form 4 filings to process")

    trades = []
    filings.each do |filing|
      break if trades.size >= limit

      transactions = parse_form4_filing(filing)
      trades.concat(transactions)
    rescue StandardError => e
      Rails.logger.warn(
        "SecEdgarForm4Client: Skipped filing #{filing[:accession_no]} — #{e.message}"
      )
    end

    Rails.logger.info("SecEdgarForm4Client: #{trades.size} insider transactions extracted")
    trades
  end

  private

  # ─── EDGAR Quarterly Index ───────────────────────────────────────────────── #

  # Downloads the quarterly Form 4 index files for every quarter that overlaps
  # the given date range and returns {cik:, accession_no:, file_date:} refs
  # capped at MAX_FILINGS.
  #
  # SEC quarterly indexes live at:
  #   https://www.sec.gov/Archives/edgar/full-index/YYYY/QTRN/form.gz
  # They cover all EDGAR form types; we filter to "4" and "4/A" lines.
  def collect_form4_filing_refs(start_date, end_date)
    refs = []

    quarters_for_range(start_date, end_date).each do |year, qtr|
      break if refs.size >= MAX_FILINGS

      new_refs = fetch_form4_from_quarterly_index(year, qtr, start_date, end_date)
      refs.concat(new_refs)
    end

    refs.first(MAX_FILINGS)
  end

  # Returns [[year, quarter], ...] for every quarter that overlaps the range.
  def quarters_for_range(start_date, end_date)
    quarters = []
    date = start_date
    while date <= end_date
      qtr = ((date.month - 1) / 3) + 1
      quarters << [date.year, qtr] unless quarters.include?([date.year, qtr])
      date = date >> 3 # advance ~one quarter
    end
    # Ensure the end_date quarter is always included
    end_qtr = ((end_date.month - 1) / 3) + 1
    quarters << [end_date.year, end_qtr] unless quarters.include?([end_date.year, end_qtr])
    quarters
  end

  def fetch_form4_from_quarterly_index(year, qtr, start_date, end_date)
    path = "/Archives/edgar/full-index/#{year}/QTR#{qtr}/form.gz"

    rate_limit
    start_time = Time.current
    response   = @filing_connection.get(path)
    duration   = ((Time.current - start_time) * 1000).to_i

    @api_calls << {
      endpoint:    "#{EDGAR_FILING_BASE}#{path}",
      status_code: response.status,
      duration_ms: duration,
      timestamp:   start_time,
      request:     { method: 'GET', endpoint: path },
      response:    { status_code: response.status }
    }

    raise "EDGAR quarterly index returned #{response.status}" unless response.status == 200

    text = decompress_gz(response.body)
    parse_form4_index_lines(text, start_date, end_date)
  rescue Faraday::Error => e
    raise "EDGAR quarterly index connection error: #{e.message}"
  end

  def decompress_gz(body)
    Zlib::GzipReader.new(StringIO.new(body.b)).read
  end

  # Parses the uncompressed form.idx text and returns filing refs for Form 4/4A
  # filings whose file_date falls within [start_date, end_date].
  #
  # Line format (fixed-width):
  #   Form Type  Company Name  CIK  Date Filed  Filename
  #   4          ACME CORP     12345  2024-01-16  edgar/data/12345/0000012345-24-000001.txt
  def parse_form4_index_lines(text, start_date, end_date)
    pattern = /\A(4(?:\/A)?)\s+.+?\s{2,}(\d+)\s+(\d{4}-\d{2}-\d{2})\s+(edgar\/data\/\S+)/

    text.each_line.filter_map do |line|
      m = line.match(pattern)
      next unless m

      file_date = Date.parse(m[3])
      next unless file_date >= start_date && file_date <= end_date

      accession_no = File.basename(m[4].strip, '.txt')
      { cik: m[2].strip, accession_no: accession_no, file_date: m[3] }
    end
  rescue ArgumentError
    []
  end

  # ─── Form 4 XML Download & Parsing ──────────────────────────────────────── #

  def parse_form4_filing(filing)
    xml_body = fetch_form4_xml(filing[:cik], filing[:accession_no])
    return [] if xml_body.nil?

    extract_transactions(xml_body, file_date: filing[:file_date])
  end

  # Fetches the Form 4 XML. Returns nil on 404 (filing uses a non-standard name).
  def fetch_form4_xml(cik, accession_no)
    accession_nodash = accession_no.delete('-')
    xml_path = "/Archives/edgar/data/#{cik}/#{accession_nodash}/form4.xml"

    rate_limit
    start_time = Time.current
    response   = @filing_connection.get(xml_path)
    duration   = ((Time.current - start_time) * 1000).to_i

    @api_calls << {
      endpoint:    "#{EDGAR_FILING_BASE}#{xml_path}",
      status_code: response.status,
      duration_ms: duration,
      timestamp:   start_time,
      request:     { method: 'GET', endpoint: xml_path, params: {} },
      response:    { status_code: response.status }
    }

    return nil if response.status == 404 # non-standard filename — skip gracefully
    raise "EDGAR filing fetch error (#{response.status}) for #{accession_no}" unless response.status == 200

    response.body
  rescue Faraday::Error => e
    Rails.logger.warn("SecEdgarForm4Client: Connection error for #{accession_no}: #{e.message}")
    nil
  end

  # Parses Form 4 XML (ownershipDocument schema) and returns transaction hashes.
  # Schema reference: https://www.sec.gov/info/edgar/ownershipxmltechspec.htm
  def extract_transactions(xml_body, file_date:)
    doc = Nokogiri::XML(xml_body) { |config| config.strict }

    ticker  = doc.at_xpath('//issuerTradingSymbol')&.text&.strip&.upcase
    return [] if ticker.blank?

    company      = doc.at_xpath('//issuerName')&.text&.strip
    trader_name  = doc.at_xpath('//rptOwnerName')&.text&.strip
    return [] if trader_name.blank?

    relationship = extract_relationship(doc)
    disclosed_at = parse_datetime(file_date)

    doc.xpath('//nonDerivativeTransaction').filter_map do |txn|
      build_transaction(txn, ticker, company, trader_name, relationship, disclosed_at)
    end
  rescue Nokogiri::XML::SyntaxError => e
    Rails.logger.warn("SecEdgarForm4Client: XML syntax error — #{e.message}")
    []
  end

  def build_transaction(txn, ticker, company, trader_name, relationship, disclosed_at)
    transaction_date = parse_date(txn.at_xpath('.//transactionDate//value')&.text)
    return nil if transaction_date.nil?

    transaction_code    = txn.at_xpath('.//transactionCode//value')&.text&.strip
    acquired_disposed   = txn.at_xpath('.//transactionAcquiredDisposedCode//value')&.text&.strip
    transaction_type    = determine_transaction_type(acquired_disposed, transaction_code)
    return nil if transaction_type.blank?

    shares  = txn.at_xpath('.//transactionShares//value')&.text.to_f
    price   = txn.at_xpath('.//transactionPricePerShare//value')&.text.to_f
    trade_value = (shares * price).round(2)

    shares_following = txn.at_xpath('.//sharesOwnedFollowingTransaction//value')&.text.to_i

    {
      ticker:           ticker,
      company:          company,
      trader_name:      trader_name,
      trader_source:    'insider',
      transaction_date: transaction_date,
      transaction_type: transaction_type,
      trade_size_usd:   trade_value.to_s,
      disclosed_at:     disclosed_at,
      relationship:     relationship,
      shares_held:      shares_following.positive? ? shares_following : nil,
      ownership_percent: nil
    }
  end

  # ─── Relationship helpers ────────────────────────────────────────────────── #

  def extract_relationship(doc)
    is_officer  = doc.at_xpath('//isOfficer')&.text&.strip == '1'
    is_director = doc.at_xpath('//isDirector')&.text&.strip == '1'
    is_ten_pct  = doc.at_xpath('//isTenPercentOwner')&.text&.strip == '1'
    title       = doc.at_xpath('//officerTitle')&.text&.strip

    if is_officer && title.present?
      classify_officer_title(title)
    elsif is_officer
      'Officer'
    elsif is_director
      'Director'
    elsif is_ten_pct
      '10% Owner'
    else
      'Other'
    end
  end

  def classify_officer_title(title)
    t = title.downcase
    if t.match?(/chief executive|\bceo\b/)                            then 'CEO'
    elsif t.match?(/chief financial|\bcfo\b/)                         then 'CFO'
    elsif t.match?(/chief operating|\bcoo\b/)                         then 'COO'
    elsif t.match?(/\bchief\b/)                                       then 'C-Suite'
    elsif t.match?(/\bpresident\b/) && !t.match?(/vice.{0,5}president/) then 'CEO'
    elsif t.match?(/\bdirector\b/)                                    then 'Director'
    else 'Officer'
    end
  end

  # ─── Transaction type helpers ────────────────────────────────────────────── #

  # Maps SEC Form 4 codes → 'Purchase' | 'Sale' | nil
  # AcquiredDisposedCode: A = Acquired, D = Disposed
  # TransactionCode:      P = Open-market purchase, S = Open-market sale,
  #                       A = Grant/award, F = Tax withholding, etc.
  def determine_transaction_type(acquired_disposed, transaction_code)
    case acquired_disposed
    when 'A' then 'Purchase'
    when 'D' then 'Sale'
    else
      case transaction_code
      when 'P' then 'Purchase'
      when 'S' then 'Sale'
      end
    end
  end

  # ─── Date helpers ────────────────────────────────────────────────────────── #

  def parse_date(str)
    return nil if str.blank?
    Date.parse(str.to_s.strip)
  rescue ArgumentError, TypeError, Date::Error
    nil
  end

  def parse_datetime(str)
    return nil if str.blank?
    DateTime.parse(str.to_s.strip)
  rescue ArgumentError, TypeError
    nil
  end

  # ─── Rate limiter ────────────────────────────────────────────────────────── #

  def rate_limit
    return if @last_request_at.nil?

    elapsed   = Time.current.to_f - @last_request_at
    sleep_for = REQUEST_INTERVAL - elapsed
    sleep(sleep_for) if sleep_for > 0
  ensure
    @last_request_at = Time.current.to_f
  end

  # ─── Faraday connections ─────────────────────────────────────────────────── #

  def build_filing_connection
    Faraday.new(url: EDGAR_FILING_BASE) do |f|
      f.headers['User-Agent'] = USER_AGENT
      f.headers['Accept']     = '*/*'
      f.options.timeout      = 60
      f.options.open_timeout = 10
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
