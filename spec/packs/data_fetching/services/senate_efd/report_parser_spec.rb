# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SenateEfd::ReportParser do
  subject(:parser) { described_class.new(session_manager) }

  let(:session_manager) { instance_double(SenateEfd::SessionManager) }

  # Realistic sample HTML structure for a Senate PTR page.
  # Based on the table.table-striped pattern described in the design doc.
  let(:ptr_html) do
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Periodic Transaction Report</title></head>
      <body>
        <h2>Periodic Transaction Report for 07/16/2026</h2>
        <p>Filer: Tuberville, Tommy (Senator)</p>

        <h3>Transactions</h3>
        <table class="table table-striped">
          <thead>
            <tr>
              <th>Transaction Date</th>
              <th>Asset Name</th>
              <th>Ticker</th>
              <th>Transaction Type</th>
              <th>Amount</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>07/15/2026</td>
              <td>Apple Inc.</td>
              <td>AAPL</td>
              <td>Purchase</td>
              <td>$15,001 - $50,000</td>
            </tr>
            <tr>
              <td>07/14/2026</td>
              <td>Microsoft Corp.</td>
              <td>MSFT</td>
              <td>Purchase</td>
              <td>$50,001 - $100,000</td>
            </tr>
            <tr>
              <td>07/13/2026</td>
              <td>Tesla, Inc.</td>
              <td>TSLA</td>
              <td>Sale (Full)</td>
              <td>$100,001 - $250,000</td>
            </tr>
          </tbody>
        </table>
      </body>
      </html>
    HTML
  end

  let(:report_path) { '/search/view/ptr/abc-123/' }
  let(:report_meta) do
    {
      first_name: 'Tommy',
      last_name: 'Tuberville',
      date_received: Date.new(2026, 7, 16)
    }
  end

  before do
    allow(session_manager).to receive_messages(cookie_header: 'csrftoken=test-csrf; sessionid=test-session',
                                               reauth_required?: false)
    allow(session_manager).to receive(:ensure_authenticated)

    stub_request(:get, "https://efdsearch.senate.gov#{report_path}")
      .with(headers: { 'Cookie' => 'csrftoken=test-csrf; sessionid=test-session' })
      .to_return(status: 200, body: ptr_html, headers: { 'Content-Type' => 'text/html' })
  end

  describe '#parse_report' do
    it 'extracts the correct number of trades' do
      trades = parser.parse_report(report_path, report_meta)
      expect(trades.size).to eq(3)
    end

    it 'sets trader_source to congress' do
      trades = parser.parse_report(report_path, report_meta)
      expect(trades).to all(include(trader_source: 'congress'))
    end

    it 'parses ticker correctly' do
      trades = parser.parse_report(report_path, report_meta)
      tickers = trades.pluck(:ticker)
      expect(tickers).to contain_exactly('AAPL', 'MSFT', 'TSLA')
    end

    it 'parses company/asset description' do
      trades = parser.parse_report(report_path, report_meta)
      companies = trades.pluck(:company)
      expect(companies).to include('Apple Inc.', 'Microsoft Corp.', 'Tesla, Inc.')
    end

    it 'parses transaction_date as a Date' do
      trades = parser.parse_report(report_path, report_meta)
      expect(trades.first[:transaction_date]).to eq(Date.new(2026, 7, 15))
    end

    it 'normalizes Purchase transaction type' do
      trades = parser.parse_report(report_path, report_meta)
      types = trades.pluck(:transaction_type)
      expect(types).to include('Purchase', 'Sale')
    end

    it 'parses the amount range' do
      trades = parser.parse_report(report_path, report_meta)
      amounts = trades.pluck(:trade_size_usd)
      expect(amounts).to include('$15,001 - $50,000', '$50,001 - $100,000')
    end

    it 'formats the trader name as Last, First' do
      trades = parser.parse_report(report_path, report_meta)
      expect(trades.first[:trader_name]).to eq('Tuberville, Tommy')
    end

    it 'sets disclosed_at from report metadata' do
      trades = parser.parse_report(report_path, report_meta)
      expect(trades.first[:disclosed_at]).to be_a(DateTime)
      expect(trades.first[:disclosed_at].to_date).to eq(Date.new(2026, 7, 16))
    end
  end

  describe 'edge cases' do
    context 'when the PTR is a PDF filing' do
      let(:ptr_html) do
        '<html><body><p>PDF Disclosed Filing</p><a href="file.pdf">Download PDF</a></body></html>'
      end

      it 'returns an empty array' do
        trades = parser.parse_report(report_path, report_meta)
        expect(trades).to be_empty
      end
    end

    context 'when a ticker is missing or "--"' do
      let(:ptr_html) do
        <<~HTML
          <html><body>
          <table class="table table-striped">
            <thead><tr><th>Date</th><th>Asset</th><th>Ticker</th><th>Type</th><th>Amount</th></tr></thead>
            <tbody>
              <tr><td>07/15/2026</td><td>Municipal Bond</td><td>--</td><td>Purchase</td><td>$15,001 - $50,000</td></tr>
              <tr><td>07/14/2026</td><td>Apple Inc.</td><td>AAPL</td><td>Purchase</td><td>$1,001 - $15,000</td></tr>
            </tbody>
          </table>
          </body></html>
        HTML
      end

      it 'skips rows with no ticker' do
        trades = parser.parse_report(report_path, report_meta)
        expect(trades.size).to eq(1)
        expect(trades.first[:ticker]).to eq('AAPL')
      end
    end

    context 'when the PTR page returns 404' do
      before do
        stub_request(:get, "https://efdsearch.senate.gov#{report_path}")
          .to_return(status: 404, body: 'Not Found')
      end

      it 'returns an empty array without raising' do
        trades = parser.parse_report(report_path, report_meta)
        expect(trades).to be_empty
      end
    end

    context 'with a table that has no header row' do
      let(:ptr_html) do
        <<~HTML
          <html><body>
          <table class="table-striped">
            <tbody>
              <tr><td>07/15/2026</td><td>Apple Inc.</td><td>AAPL</td><td>Purchase</td><td>$15,001 - $50,000</td></tr>
            </tbody>
          </table>
          </body></html>
        HTML
      end

      it 'falls back to finding a table with transaction-like content' do
        # Even without `table.table-striped` class, it should find the table
        # via the fallback header/content search.
        trades = parser.parse_report(report_path, report_meta)
        expect(trades.size).to eq(1)
      end
    end
  end

  describe '#api_calls' do
    it 'records API call metadata' do
      parser.parse_report(report_path, report_meta)
      expect(parser.api_calls).not_to be_empty
      expect(parser.api_calls.first[:endpoint]).to include(report_path)
    end
  end
end
