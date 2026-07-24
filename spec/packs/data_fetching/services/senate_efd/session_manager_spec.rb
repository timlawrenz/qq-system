# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SenateEfd::SessionManager do
  subject(:session) { described_class.new }

  let(:home_page_html) do
    <<~HTML
      <html>
      <body>
        <form method="post">
          <input type="hidden" name="csrfmiddlewaretoken" value="test-csrf-token-abc123" />
          <input type="hidden" name="prohibition_agreement" value="1" />
        </form>
      </body>
      </html>
    HTML
  end

  let(:session_cookie) { 'sessionid=test-session-id-xyz789; Path=/; HttpOnly' }

  before do
    # Stub the home page GET — returns an initial csrftoken cookie
    stub_request(:get, 'https://efdsearch.senate.gov/search/home/')
      .to_return(
        status: 200,
        body: home_page_html,
        headers: {
          'Content-Type' => 'text/html',
          'Set-Cookie' => 'csrftoken=initial-csrftoken-cookie; Path=/'
        }
      )

    # Stub the agreement POST — returns a sessionid cookie
    stub_request(:post, 'https://efdsearch.senate.gov/search/home/')
      .with(
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
      )
      .to_return(
        status: 302,
        body: '',
        headers: {
          'Location' => '/search/',
          'Set-Cookie' => session_cookie
        }
      )
  end

  describe '#ensure_authenticated' do
    it 'returns true on success' do
      expect(session.ensure_authenticated).to be true
    end

    it 'sets authenticated_at timestamp' do
      expect { session.ensure_authenticated }
        .to change(session, :authenticated_at).from(nil)
    end
  end

  describe '#cookie_header' do
    before { session.ensure_authenticated }

    it 'includes the csrftoken cookie' do
      expect(session.cookie_header).to include('csrftoken=')
    end

    it 'includes the sessionid cookie' do
      expect(session.cookie_header).to include('sessionid=')
    end
  end

  describe '#csrf_token_value' do
    before { session.ensure_authenticated }

    it 'returns the CSRF token extracted from the home page' do
      expect(session.csrf_token_value).to eq('test-csrf-token-abc123')
    end
  end

  describe '#reauth_required?' do
    context 'when response is a redirect to the home page' do
      let(:response) do
        double(status: 302, '[]' => '/search/home/')
      end

      it 'returns true' do
        expect(session.reauth_required?(response)).to be true
      end
    end

    context 'when response is a normal 200' do
      let(:response) do
        double(status: 200, '[]' => nil)
      end

      it 'returns false' do
        expect(session.reauth_required?(response)).to be false
      end
    end
  end

  describe 'authentication failure' do
    context 'when the home page does not contain a CSRF token' do
      let(:home_page_html) { '<html><body>No token here</body></html>' }

      it 'raises AuthError' do
        expect { session.ensure_authenticated }
          .to raise_error(SenateEfd::SessionManager::AuthError, /csrfmiddlewaretoken/)
      end
    end

    context 'when the agreement POST does not set a sessionid' do
      let(:session_cookie) { '' }

      it 'raises AuthError' do
        expect { session.ensure_authenticated }
          .to raise_error(SenateEfd::SessionManager::AuthError, /sessionid/)
      end
    end
  end

  describe 'session freshness' do
    context 'when session was authenticated recently' do
      before { session.ensure_authenticated }

      it 'does not re-authenticate on cookie_header' do
        # The first call authenticated; second should skip
        expect(session).not_to receive(:ensure_authenticated).and_call_original
        session.cookie_header
      end
    end
  end
end
