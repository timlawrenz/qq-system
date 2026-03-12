# frozen_string_literal: true

require 'rails_helper'
require 'zlib'

RSpec.describe SecEdgarForm4Client do
  subject(:client) { described_class.new }

  # Minimal valid Form 4 XML (ownershipDocument schema)
  def form4_xml(ticker: 'AAPL', name: 'DOE JOHN', officer: true, title: 'Chief Executive Officer',
                acquired_disposed: 'A', transaction_code: 'P',
                shares: '10000', price: '150.00', shares_following: '50000',
                transaction_date: '2024-01-15')
    <<~XML
      <?xml version="1.0"?>
      <ownershipDocument>
        <issuer>
          <issuerCik>0000320193</issuerCik>
          <issuerName>#{ticker == 'AAPL' ? 'APPLE INC' : ticker}</issuerName>
          <issuerTradingSymbol>#{ticker}</issuerTradingSymbol>
        </issuer>
        <reportingOwner>
          <reportingOwnerId>
            <rptOwnerName>#{name}</rptOwnerName>
          </reportingOwnerId>
          <reportingOwnerRelationship>
            <isDirector>0</isDirector>
            <isOfficer>#{officer ? 1 : 0}</isOfficer>
            <isTenPercentOwner>0</isTenPercentOwner>
            <officerTitle>#{title}</officerTitle>
          </reportingOwnerRelationship>
        </reportingOwner>
        <nonDerivativeTable>
          <nonDerivativeTransaction>
            <securityTitle><value>Common Stock</value></securityTitle>
            <transactionDate><value>#{transaction_date}</value></transactionDate>
            <transactionCoding>
              <transactionCode><value>#{transaction_code}</value></transactionCode>
            </transactionCoding>
            <transactionAmounts>
              <transactionShares><value>#{shares}</value></transactionShares>
              <transactionPricePerShare><value>#{price}</value></transactionPricePerShare>
              <transactionAcquiredDisposedCode><value>#{acquired_disposed}</value></transactionAcquiredDisposedCode>
            </transactionAmounts>
            <postTransactionAmounts>
              <sharesOwnedFollowingTransaction><value>#{shares_following}</value></sharesOwnedFollowingTransaction>
            </postTransactionAmounts>
          </nonDerivativeTransaction>
        </nonDerivativeTable>
        <periodOfReport>#{transaction_date}</periodOfReport>
      </ownershipDocument>
    XML
  end

  # Builds a gzip-compressed form.gz index body containing the given lines.
  def build_index_gz(lines)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    gz.write(lines.join("\n"))
    gz.close
    io.string
  end

  let(:index_gz_body) do
    build_index_gz([
      "4                APPLE INC                                                     320193      2024-01-16  edgar/data/320193/0000320193-24-000001.txt"
    ])
  end

  let(:form4_xml_body) { form4_xml }

  before do
    stub_request(:get, %r{www\.sec\.gov/Archives/edgar/full-index/\d+/QTR\d+/form\.gz})
      .to_return(status: 200, body: index_gz_body, headers: { 'Content-Type' => 'application/x-gzip' })

    stub_request(:get, %r{www\.sec\.gov/Archives/edgar/data/320193/000032019324000001/form4\.xml})
      .to_return(status: 200, body: form4_xml_body, headers: { 'Content-Type' => 'application/xml' })
  end

  describe '#fetch_insider_trades' do
    subject(:trades) do
      client.fetch_insider_trades(
        start_date: Date.new(2024, 1, 10),
        end_date: Date.new(2024, 1, 20)
      )
    end

    it 'returns an array of trade hashes' do
      expect(trades).to be_an(Array)
      expect(trades.size).to eq(1)
    end

    describe 'parsed trade fields' do
      let(:trade) { trades.first }

      it 'sets ticker from XML issuerTradingSymbol' do
        expect(trade[:ticker]).to eq('AAPL')
      end

      it 'sets company from XML issuerName' do
        expect(trade[:company]).to eq('APPLE INC')
      end

      it 'sets trader_name from XML rptOwnerName' do
        expect(trade[:trader_name]).to eq('DOE JOHN')
      end

      it 'sets trader_source to insider' do
        expect(trade[:trader_source]).to eq('insider')
      end

      it 'sets transaction_date from XML' do
        expect(trade[:transaction_date]).to eq(Date.new(2024, 1, 15))
      end

      it 'maps AcquiredDisposedCode A to Purchase' do
        expect(trade[:transaction_type]).to eq('Purchase')
      end

      it 'computes trade_size_usd as shares * price' do
        expect(trade[:trade_size_usd]).to eq('1500000.0')
      end

      it 'sets disclosed_at from filing date' do
        expect(trade[:disclosed_at]).to be_a(DateTime)
        expect(trade[:disclosed_at].to_date).to eq(Date.new(2024, 1, 16))
      end

      it 'sets relationship to CEO for chief executive title' do
        expect(trade[:relationship]).to eq('CEO')
      end

      it 'sets shares_held from sharesOwnedFollowingTransaction' do
        expect(trade[:shares_held]).to eq(50_000)
      end
    end

    context 'with AcquiredDisposedCode D (Sale)' do
      let(:form4_xml_body) { form4_xml(acquired_disposed: 'D', transaction_code: 'S') }

      it 'maps to Sale' do
        expect(trades.first[:transaction_type]).to eq('Sale')
      end
    end

    context 'with non-purchase/sale transaction codes (e.g. Award)' do
      let(:form4_xml_body) { form4_xml(acquired_disposed: nil.to_s, transaction_code: 'A') }

      it 'skips transactions with no clear type' do
        expect(trades).to be_empty
      end
    end

    context 'when Form 4 XML has no issuerTradingSymbol' do
      let(:form4_xml_body) do
        <<~XML
          <?xml version="1.0"?>
          <ownershipDocument>
            <issuer><issuerName>UNKNOWN CO</issuerName></issuer>
            <reportingOwner>
              <reportingOwnerId><rptOwnerName>DOE JOHN</rptOwnerName></reportingOwnerId>
            </reportingOwner>
          </ownershipDocument>
        XML
      end

      it 'skips the filing and returns empty array' do
        expect(trades).to be_empty
      end
    end

    context 'when Form 4 XML returns 404' do
      before do
        stub_request(:get, %r{www\.sec\.gov/Archives/edgar/data/320193/000032019324000001/form4\.xml})
          .to_return(status: 404, body: '')
      end

      it 'skips the filing gracefully' do
        expect(trades).to be_empty
      end
    end

    context 'when the EDGAR quarterly index returns an error' do
      before do
        stub_request(:get, %r{www\.sec\.gov/Archives/edgar/full-index})
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'raises an error' do
        expect { trades }.to raise_error(StandardError, /EDGAR quarterly index/)
      end
    end
  end

  describe '#api_calls' do
    before do
      client.fetch_insider_trades(
        start_date: Date.new(2024, 1, 10),
        end_date: Date.new(2024, 1, 20)
      )
    end

    it 'records one call for the quarterly index download' do
      index_calls = client.api_calls.select { |c| c[:endpoint].include?('full-index') }
      expect(index_calls.size).to eq(1)
    end

    it 'records one call for the Form 4 XML download' do
      xml_calls = client.api_calls.select { |c| c[:endpoint].include?('Archives/edgar/data') }
      expect(xml_calls.size).to eq(1)
    end
  end

  describe 'relationship classification' do
    {
      'Chief Executive Officer' => 'CEO',
      'Chief Financial Officer' => 'CFO',
      'Chief Operating Officer' => 'COO',
      'Chief Technology Officer' => 'C-Suite',
      'Director'                => 'Director',
      'Vice President'          => 'Officer'
    }.each do |title, expected|
      context "with officer title '#{title}'" do
        let(:form4_xml_body) { form4_xml(title: title) }

        it "classifies as #{expected}" do
          trade = client.fetch_insider_trades(
            start_date: Date.new(2024, 1, 10),
            end_date: Date.new(2024, 1, 20)
          ).first
          expect(trade[:relationship]).to eq(expected)
        end
      end
    end
  end
end
