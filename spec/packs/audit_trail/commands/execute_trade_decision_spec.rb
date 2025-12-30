# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditTrail::ExecuteTradeDecision do
  let(:decision) { create(:trade_decision, status: 'pending') }
  let(:alpaca_service) { instance_double(AlpacaService) }

  before do
    allow(AlpacaService).to receive(:new).and_return(alpaca_service)
  end

  describe '.call' do
    context 'when trade is successful' do
      before do
        allow(alpaca_service).to receive(:place_order).and_return(
          {
            'id' => 'order-123',
            'status' => 'filled',
            'qty' => 10,
            'filled_qty' => 10,
            'filled_avg_price' => 150.25
          }
        )
      end

      it 'creates a TradeExecution record and updates decision status' do
        expect do
          described_class.call(trade_decision: decision)
        end.to change(AuditTrail::TradeExecution, :count).by(1)

        expect(decision.reload.status).to eq('executed')
        expect(decision.executed_at).to be_present

        execution = AuditTrail::TradeExecution.last
        expect(execution.status).to eq('filled')
        expect(execution.alpaca_order_id).to eq('order-123')
        expect(execution.api_request_payload).to be_present
        expect(execution.api_response_payload).to be_present
      end
    end

    context 'when trade is rejected' do
      before do
        allow(alpaca_service).to receive(:place_order).and_return(
          {
            'status' => 'rejected',
            'message' => 'insufficient buying power',
            'http_status' => 403
          }
        )
      end

      it 'creates a failed TradeExecution and updates decision status' do
        described_class.call(trade_decision: decision)

        expect(decision.reload.status).to eq('failed')
        expect(decision.failed_at).to be_present

        execution = AuditTrail::TradeExecution.last
        expect(execution.status).to eq('rejected')
        expect(execution.error_message).to eq('insufficient buying power')
        expect(execution.http_status_code).to eq(403)
      end
    end

    context 'when AlpacaService raises an error' do
      before do
        allow(alpaca_service).to receive(:place_order).and_raise(StandardError, 'Network error')
      end

      it 'captures error and fails the decision' do
        # The command itself should succeed (it handles the error by logging it)
        # Wait, my implementation re-raises if not standard? No, it catches StandardError.
        result = described_class.call(trade_decision: decision)

        expect(result.success?).to be true
        expect(decision.reload.status).to eq('failed')

        execution = AuditTrail::TradeExecution.last
        expect(execution.status).to eq('rejected')
        expect(execution.error_message).to eq('Network error')
      end
    end

    context 'when decision is not pending' do
      let(:executed_decision) { create(:trade_decision, :executed) }

      it 'fails the command' do
        result = described_class.call(trade_decision: executed_decision)
        expect(result.success?).to be false
        expect(result.full_error_message).to include('is not pending')
      end
    end
  end
end
