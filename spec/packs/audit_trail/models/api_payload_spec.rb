# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditTrail::ApiPayload, type: :model do
  describe 'validations' do
    it 'requires type' do
      payload = build(:api_payload, type: nil)
      expect(payload).not_to be_valid
    end

    it 'requires source' do
      payload = build(:api_payload, source: nil)
      expect(payload).not_to be_valid
    end

    it 'validates source inclusion' do
      payload = build(:api_payload, source: 'invalid')
      expect(payload).not_to be_valid
    end

    it 'requires captured_at' do
      payload = build(:api_payload, captured_at: nil)
      expect(payload).not_to be_valid
    end
  end

  describe 'STI' do
    it 'creates an ApiRequest when type is AuditTrail::ApiRequest' do
      request = AuditTrail::ApiRequest.create!(
        source: 'alpaca',
        captured_at: Time.current,
        payload: { endpoint: '/v2/orders' }
      )
      expect(request).to be_a(AuditTrail::ApiRequest)
      expect(AuditTrail::ApiPayload.find(request.id)).to be_a(AuditTrail::ApiRequest)
    end

    it 'creates an ApiResponse when type is AuditTrail::ApiResponse' do
      response = AuditTrail::ApiResponse.create!(
        source: 'alpaca',
        captured_at: Time.current,
        payload: { status_code: 200 }
      )
      expect(response).to be_a(AuditTrail::ApiResponse)
      expect(AuditTrail::ApiPayload.find(response.id)).to be_a(AuditTrail::ApiResponse)
    end
  end
end
