# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsaSpendingClient do
  subject(:client) { described_class.new }

  let(:ticker)     { 'LMT' }
  let(:start_date) { Date.new(2024, 1, 1) }
  let(:end_date)   { Date.new(2024, 1, 31) }

  let(:usaspending_response) do
    {
      'results' => [
        {
          'Award ID'            => 'FA8635-24-C-0001',
          'Recipient Name'      => 'LOCKHEED MARTIN CORPORATION',
          'Award Amount'        => 85_000_000.0,
          'Start Date'          => '2024-01-12',
          'Awarding Agency Name' => 'Department of Defense',
          'Description'         => 'F-35 production contract',
          'Contract Award Type' => 'C'
        },
        {
          'Award ID'            => 'FA8635-24-C-0002',
          'Recipient Name'      => 'LOCKHEED MARTIN AERONAUTICS',
          'Award Amount'        => 12_500_000.0,
          'Start Date'          => '2024-01-20',
          'Awarding Agency Name' => 'US Air Force',
          'Description'         => 'Maintenance services',
          'Contract Award Type' => 'B'
        }
      ],
      'page_metadata' => { 'page' => 1, 'limit' => 100, 'total' => 2 }
    }.to_json
  end

  before do
    # CompanyProfile with company_name so the client can resolve ticker → name
    CompanyProfile.create!(
      ticker: 'LMT',
      company_name: 'Lockheed Martin',
      source: 'fmp',
      fetched_at: 1.hour.ago
    )

    stub_request(:post, "#{described_class::BASE_URL}#{described_class::AWARDS_ENDPOINT}")
      .to_return(status: 200, body: usaspending_response,
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe '#fetch_government_contracts' do
    subject(:contracts) do
      client.fetch_government_contracts(ticker: ticker, start_date: start_date, end_date: end_date)
    end

    it 'returns contracts with normalized fields' do
      expect(contracts.size).to eq(2)

      first = contracts.first
      expect(first[:contract_id]).to eq('FA8635-24-C-0001')
      expect(first[:ticker]).to eq('LMT')
      expect(first[:company]).to eq('LOCKHEED MARTIN CORPORATION')
      expect(first[:contract_value]).to eq(BigDecimal('85000000.0'))
      expect(first[:award_date]).to eq(Date.new(2024, 1, 12))
      expect(first[:agency]).to eq('Department of Defense')
      expect(first[:contract_type]).to eq('C')
    end

    it 'includes disclosed_at as nil (not provided by USASpending)' do
      expect(contracts.first[:disclosed_at]).to be_nil
    end

    context 'when CompanyProfile is missing for the ticker' do
      before { CompanyProfile.find_by(ticker: 'LMT').destroy }

      it 'returns an empty array and logs a warning' do
        expect(contracts).to be_empty
      end

      it 'makes no HTTP requests' do
        contracts
        expect(a_request(:post, "#{described_class::BASE_URL}#{described_class::AWARDS_ENDPOINT}"))
          .not_to have_been_made
      end
    end

    context 'when the API returns an empty results array' do
      before do
        stub_request(:post, "#{described_class::BASE_URL}#{described_class::AWARDS_ENDPOINT}")
          .to_return(status: 200,
                     body: { 'results' => [], 'page_metadata' => { 'total' => 0 } }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns an empty array' do
        expect(contracts).to be_empty
      end
    end

    context 'when a result row has a zero award amount' do
      before do
        stub_request(:post, "#{described_class::BASE_URL}#{described_class::AWARDS_ENDPOINT}")
          .to_return(status: 200,
                     body: {
                       'results' => [
                         { 'Award ID' => 'ID-001', 'Recipient Name' => 'X', 'Award Amount' => 0,
                           'Start Date' => '2024-01-10', 'Awarding Agency Name' => 'DoD',
                           'Description' => nil, 'Contract Award Type' => 'B' }
                       ]
                     }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'filters out zero-value awards' do
        expect(contracts).to be_empty
      end
    end

    context 'when a result row is missing a date' do
      before do
        stub_request(:post, "#{described_class::BASE_URL}#{described_class::AWARDS_ENDPOINT}")
          .to_return(status: 200,
                     body: {
                       'results' => [
                         { 'Award ID' => 'ID-002', 'Recipient Name' => 'X', 'Award Amount' => 1_000_000,
                           'Start Date' => nil, 'Awarding Agency Name' => 'DoD',
                           'Description' => nil, 'Contract Award Type' => 'C' }
                       ]
                     }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'skips records with no date' do
        expect(contracts).to be_empty
      end
    end

    context 'when the API returns a non-200 status' do
      before do
        stub_request(:post, "#{described_class::BASE_URL}#{described_class::AWARDS_ENDPOINT}")
          .to_return(status: 429, body: 'Too Many Requests')
      end

      it 'returns an empty array without raising' do
        expect(contracts).to be_empty
      end
    end
  end

  describe '#api_calls' do
    it 'records one api_call per HTTP request made' do
      client.fetch_government_contracts(ticker: ticker, start_date: start_date, end_date: end_date)
      expect(client.api_calls.size).to eq(1)
    end

    it 'captures the endpoint and status code' do
      client.fetch_government_contracts(ticker: ticker, start_date: start_date, end_date: end_date)
      call = client.api_calls.first
      expect(call[:endpoint]).to eq(described_class::AWARDS_ENDPOINT)
      expect(call[:status_code]).to eq(200)
    end

    it 'records no calls when company profile is missing' do
      CompanyProfile.find_by(ticker: 'LMT').destroy
      client.fetch_government_contracts(ticker: ticker, start_date: start_date, end_date: end_date)
      expect(client.api_calls).to be_empty
    end
  end
end
