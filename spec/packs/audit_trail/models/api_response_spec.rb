# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditTrail::ApiResponse, type: :model do
  describe 'helper methods' do
    let(:payload) do
      {
        'status_code' => 200,
        'body' => '{"status":"ok"}',
        'id' => 'order-123',
        'filled_qty' => '10',
        'filled_avg_price' => '150.0'
      }
    end
    let(:response) { build(:api_response, payload: payload) }

    it '#status_code returns status_code from payload' do
      expect(response.status_code).to eq(200)
    end

    it '#success? returns true for 2xx' do
      expect(response.success?).to be true
    end

    it '#error? returns false for 2xx' do
      expect(response.error?).to be false
    end

    it '#order_id returns id from payload' do
      expect(response.order_id).to eq('order-123')
    end

    it '#filled_qty returns filled_qty from payload' do
      expect(response.filled_qty).to eq('10')
    end

    it '#filled_avg_price returns filled_avg_price from payload' do
      expect(response.filled_avg_price).to eq('150.0')
    end
  end

  describe 'error detection' do
    it '#success? returns false for 4xx' do
      response = build(:api_response, payload: { 'status_code' => 403 })
      expect(response.success?).to be false
    end

    it '#error? returns true for 4xx' do
      response = build(:api_response, payload: { 'status_code' => 403 })
      expect(response.error?).to be true
    end

    it '#error_message returns message from payload' do
      response = build(:api_response, payload: { 'status_code' => 403, 'message' => 'Forbidden' })
      expect(response.error_message).to eq('Forbidden')
    end
  end
end
