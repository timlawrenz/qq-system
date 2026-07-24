# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SenateEfd::IndexFetcher do
  subject(:fetcher) { described_class.new(session_manager) }

  let(:session_manager) { instance_double(SenateEfd::SessionManager) }

  let(:data_tables_response) do
    {
      'draw' => 1,
      'recordsTotal' => 3,
      'recordsFiltered' => 3,
      'data' => [
        [
          'Thomas H',
          'Tuberville',
          'Tuberville, Tommy (Senator)',
          '<a href="/search/view/ptr/abc-123/" target="_blank">' \
          'Periodic Transaction Report for 07/16/2026</a>',
          '07/16/2026'
        ],
        [
          'John',
          'Boozman',
          'Boozman, John (Senator)',
          '<a href="/search/view/ptr/def-456/" target="_blank">' \
          'Periodic Transaction Report for 07/15/2026</a>',
          '07/15/2026'
        ],
        [
          'Jane',
          'Doe',
          'Doe, Jane (Senator)',
          '<a href="/search/view/ptr/ghi-789/" target="_blank">' \
          'Periodic Transaction Report for 07/14/2026</a>',
          '07/14/2026'
        ]
      ]
    }.to_json
  end

  let(:empty_response) do
    { 'draw' => 1, 'recordsTotal' => 0, 'recordsFiltered' => 0, 'data' => [] }.to_json
  end

  before do
    allow(session_manager).to receive_messages(
      cookie_header: 'csrftoken=test-csrf; sessionid=test-session',
      csrf_token_value: 'test-csrf-token',
      authenticated_at: Time.current,
      reauth_required?: false
    )
    allow(session_manager).to receive(:ensure_authenticated)

    # Stub jitter sleep to keep tests fast
    allow_any_instance_of(described_class).to receive(:jitter_sleep) # rubocop:disable RSpec/AnyInstance
  end

  describe '#fetch_ptrs_since' do
    context 'with a single page of results' do
      before do
        stub_request(:post, 'https://efdsearch.senate.gov/search/report/data/')
          .with(
            headers: {
              'Cookie' => 'csrftoken=test-csrf; sessionid=test-session',
              'X-CSRFToken' => 'test-csrf-token'
            }
          )
          .to_return(status: 200, body: data_tables_response,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns parsed report metadata' do
        results = fetcher.fetch_ptrs_since(Date.new(2026, 1, 1))

        expect(results.size).to eq(3)
      end

      it 'parses first_name correctly' do
        results = fetcher.fetch_ptrs_since(Date.new(2026, 1, 1))
        expect(results.first[:first_name]).to eq('Thomas H')
      end

      it 'parses last_name correctly' do
        results = fetcher.fetch_ptrs_since(Date.new(2026, 1, 1))
        expect(results.first[:last_name]).to eq('Tuberville')
      end

      it 'extracts the URL path from the anchor tag' do
        results = fetcher.fetch_ptrs_since(Date.new(2026, 1, 1))
        expect(results.first[:url]).to eq('/search/view/ptr/abc-123/')
      end

      it 'parses date_received as a Date' do
        results = fetcher.fetch_ptrs_since(Date.new(2026, 1, 1))
        expect(results.first[:date_received]).to eq(Date.new(2026, 7, 16))
      end
    end

    context 'with no results' do
      before do
        stub_request(:post, 'https://efdsearch.senate.gov/search/report/data/')
          .to_return(status: 200, body: empty_response,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns an empty array' do
        results = fetcher.fetch_ptrs_since(Date.new(2026, 1, 1))
        expect(results).to be_empty
      end
    end

    context 'when the API returns a non-200 status' do
      before do
        stub_request(:post, 'https://efdsearch.senate.gov/search/report/data/')
          .to_return(status: 503, body: 'Service Unavailable')
      end

      it 'raises ApiError' do
        expect { fetcher.fetch_ptrs_since(Date.new(2026, 1, 1)) }
          .to raise_error(SenateEfd::IndexFetcher::ApiError)
      end
    end

    context 'with watermark date' do
      before do
        stub_request(:post, 'https://efdsearch.senate.gov/search/report/data/')
          .to_return(status: 200, body: data_tables_response,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'passes the watermark as submitted_start_date' do
        fetcher.fetch_ptrs_since(Date.new(2026, 6, 1))

        expect(WebMock).to have_requested(
          :post,
          'https://efdsearch.senate.gov/search/report/data/'
        ).with(
          body: /submitted_start_date=06%2F01%2F2026\+00%3A00%3A00/
        )
      end
    end

    context 'when session expires mid-request' do
      before do
        call_count = 0
        stub_request(:post, 'https://efdsearch.senate.gov/search/report/data/')
          .to_return do
            call_count += 1
            if call_count == 1
              # First call: session expired → redirect
              {
                status: 302,
                headers: { 'Location' => 'https://efdsearch.senate.gov/search/home/' }
              }
            else
              # Second call: after re-auth, works
              { status: 200, body: data_tables_response,
                headers: { 'Content-Type' => 'application/json' } }
            end
        end

        allow(session_manager).to receive(:reauth_required?).and_return(true, false)
      end

      it 're-authenticates and retries' do
        results = fetcher.fetch_ptrs_since(Date.new(2026, 1, 1))
        expect(results.size).to eq(3)
        expect(session_manager).to have_received(:ensure_authenticated)
      end
    end

    context 'with a nil watermark_date' do
      before do
        stub_request(:post, 'https://efdsearch.senate.gov/search/report/data/')
          .to_return(status: 200, body: data_tables_response,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'does not set submitted_start_date' do
        fetcher.fetch_ptrs_since(nil)
        expect(WebMock).to have_requested(
          :post, 'https://efdsearch.senate.gov/search/report/data/'
        ).with(body: /submitted_start_date=&/)
      end
    end
  end

  describe '#api_calls' do
    before do
      stub_request(:post, 'https://efdsearch.senate.gov/search/report/data/')
        .to_return(status: 200, body: data_tables_response,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'records API call metadata' do
      fetcher.fetch_ptrs_since(Date.new(2026, 1, 1))
      expect(fetcher.api_calls).not_to be_empty
      expect(fetcher.api_calls.first[:endpoint]).to include('/search/report/data/')
      expect(fetcher.api_calls.first[:status_code]).to eq(200)
    end
  end
end
