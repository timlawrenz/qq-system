# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditTrail::ApiRequest, type: :model do
  describe 'validations' do
    it 'requires endpoint in payload' do
      request = build(:api_request, payload: { method: 'GET' })
      expect(request).not_to be_valid
      expect(request.errors[:payload]).to include('must include endpoint')
    end

    it 'is valid with endpoint' do
      request = build(:api_request, payload: { endpoint: '/test' })
      expect(request).to be_valid
    end
  end

  describe 'helper methods' do
    let(:payload) do
      {
        'endpoint' => '/v2/orders',
        'method' => 'POST',
        'params' => { 'symbol' => 'AAPL' },
        'headers' => { 'Content-Type' => 'application/json' }
      }
    end
    let(:request) { build(:api_request, payload: payload) }

    it '#endpoint returns endpoint from payload' do
      expect(request.endpoint).to eq('/v2/orders')
    end

    it '#http_method returns method from payload' do
      expect(request.http_method).to eq('POST')
    end

    it '#params returns params from payload' do
      expect(request.params).to eq({ 'symbol' => 'AAPL' })
    end

    it '#headers returns headers from payload' do
      expect(request.headers).to eq({ 'Content-Type' => 'application/json' })
    end
  end
end
