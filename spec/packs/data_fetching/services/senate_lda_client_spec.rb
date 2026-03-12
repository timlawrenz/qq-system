# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SenateLdaClient do
  subject(:client) { described_class.new }

  let(:ticker)     { 'GOOGL' }
  let(:start_date) { Date.new(2024, 1, 1) }
  let(:end_date)   { Date.new(2024, 6, 30) }

  let(:lda_response) do
    {
      'count' => 2,
      'next' => nil,
      'results' => [
        {
          'filing_dt_posted' => '2024-04-15',
          'period_code' => 'Q1',
          'period_year' => 2024,
          'income' => '120000.00',
          'expenses' => nil,
          'registrant' => { 'name' => 'Capitol Strategies LLC' },
          'client' => { 'client_name' => 'Alphabet Inc.' },
          'lobbying_activities' => [
            { 'general_issue_code' => 'TAX', 'description' => 'Corporate tax reform' },
            { 'general_issue_code' => 'TEC', 'description' => 'AI regulation' }
          ]
        },
        {
          'filing_dt_posted' => '2024-04-20',
          'period_code' => 'Q1',
          'period_year' => 2024,
          'income' => '85000.00',
          'expenses' => nil,
          'registrant' => { 'name' => 'Beltway Partners Inc' },
          'client' => { 'client_name' => 'Google LLC' },
          'lobbying_activities' => [
            { 'general_issue_code' => 'CPY', 'description' => 'Copyright legislation' }
          ]
        }
      ]
    }.to_json
  end

  before do
    CompanyProfile.create!(
      ticker: 'GOOGL',
      company_name: 'Alphabet Inc',
      source: 'fmp',
      fetched_at: 1.hour.ago
    )

    stub_request(:get, %r{lda\.senate\.gov/api/v1/filings})
      .to_return(status: 200, body: lda_response,
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe '#fetch_lobbying_data' do
    subject(:records) do
      client.fetch_lobbying_data(ticker, start_date: start_date, end_date: end_date)
    end

    it 'returns normalised lobbying records' do
      expect(records.size).to eq(2)

      first = records.first
      expect(first[:ticker]).to eq('GOOGL')
      expect(first[:date]).to eq(Date.new(2024, 4, 15))
      expect(first[:quarter]).to eq('Q1 2024')
      expect(first[:amount]).to eq(BigDecimal('120000.00'))
      expect(first[:registrant]).to eq('Capitol Strategies LLC')
      expect(first[:client]).to eq('Alphabet Inc.')
    end

    it 'aggregates issue codes from lobbying activities' do
      expect(records.first[:issue]).to eq('TAX, TEC')
    end

    it 'aggregates specific issue descriptions (up to 3)' do
      expect(records.first[:specific_issue]).to include('Corporate tax reform')
      expect(records.first[:specific_issue]).to include('AI regulation')
    end

    context 'when CompanyProfile is missing for the ticker' do
      before { CompanyProfile.find_by(ticker: 'GOOGL').destroy }

      it 'returns an empty array' do
        expect(records).to be_empty
      end

      it 'makes no HTTP requests' do
        records
        expect(a_request(:get, %r{lda\.senate\.gov/api/v1/filings}))
          .not_to have_been_made
      end
    end

    context 'when the API returns no results' do
      before do
        stub_request(:get, %r{lda\.senate\.gov/api/v1/filings})
          .to_return(status: 200,
                     body: { 'count' => 0, 'next' => nil, 'results' => [] }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns an empty array' do
        expect(records).to be_empty
      end
    end

    context 'when a filing has no filing date' do
      before do
        stub_request(:get, %r{lda\.senate\.gov/api/v1/filings})
          .to_return(status: 200,
                     body: {
                       'count' => 1,
                       'next' => nil,
                       'results' => [
                         { 'filing_dt_posted' => nil, 'period_code' => 'Q1', 'period_year' => 2024,
                           'income' => '50000', 'registrant' => { 'name' => 'Firm X' },
                           'client' => { 'client_name' => 'Alphabet Inc.' },
                           'lobbying_activities' => [] }
                       ]
                     }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'skips the record' do
        expect(records).to be_empty
      end
    end

    context 'when the API returns a non-200 status' do
      before do
        stub_request(:get, %r{lda\.senate\.gov/api/v1/filings})
          .to_return(status: 503, body: 'Service Unavailable')
      end

      it 'returns an empty array without raising' do
        expect(records).to be_empty
      end
    end

    context 'when period_code is missing' do
      before do
        stub_request(:get, %r{lda\.senate\.gov/api/v1/filings})
          .to_return(status: 200,
                     body: {
                       'count' => 1,
                       'next' => nil,
                       'results' => [
                         { 'filing_dt_posted' => '2024-05-10', 'period_code' => nil, 'period_year' => nil,
                           'income' => '75000', 'registrant' => { 'name' => 'Firm Y' },
                           'client' => { 'client_name' => 'Alphabet Inc.' },
                           'lobbying_activities' => [] }
                       ]
                     }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'derives quarter from the filing date' do
        expect(records.first[:quarter]).to eq('Q2 2024')
      end
    end
  end

  describe '#api_calls' do
    it 'records one api_call per HTTP request' do
      client.fetch_lobbying_data(ticker, start_date: start_date, end_date: end_date)
      expect(client.api_calls.size).to eq(1)
    end

    it 'captures endpoint and status code' do
      client.fetch_lobbying_data(ticker, start_date: start_date, end_date: end_date)
      call = client.api_calls.first
      expect(call[:endpoint]).to eq(described_class::FILINGS_ENDPOINT)
      expect(call[:status_code]).to eq(200)
    end

    it 'records no calls when company profile is missing' do
      CompanyProfile.find_by(ticker: 'GOOGL').destroy
      client.fetch_lobbying_data(ticker, start_date: start_date, end_date: end_date)
      expect(client.api_calls).to be_empty
    end
  end
end
