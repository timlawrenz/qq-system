# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trade Execution Flow' do
  let(:symbol) { 'AAPL' }
  let(:quantity) { 100 }
  let(:strategy_name) { 'CongressionalTradingStrategy' }

  it 'executes complete flow: decision → execution → result' do
    # 1. Create decision
    decision_cmd = AuditTrail::CreateTradeDecision.call(
      strategy_name: strategy_name,
      symbol: symbol,
      side: 'buy',
      quantity: quantity,
      rationale: { signal_strength: 8.5 }
    )
    
    expect(decision_cmd.success?).to be true
    decision = decision_cmd.trade_decision
    expect(decision.status).to eq('pending')

    # 2. Mock Alpaca API
    # We mock the service because we don't want real API calls in integration tests
    alpaca_double = instance_double(AlpacaService)
    allow(AlpacaService).to receive(:new).and_return(alpaca_double)
    allow(alpaca_double).to receive(:place_order).and_return({
      'id' => 'order-123',
      'status' => 'filled',
      'qty' => quantity.to_s,
      'filled_qty' => quantity.to_s,
      'filled_avg_price' => '150.25',
      'submitted_at' => Time.current.to_s
    })

    # 3. Execute trade
    execution_cmd = AuditTrail::ExecuteTradeDecision.call(
      trade_decision: decision
    )
    
    expect(execution_cmd.success?).to be true
    
    # 4. Verify complete audit trail
    decision.reload
    execution = execution_cmd.trade_execution
    
    # Decision status updated
    expect(decision.status).to eq('executed')
    expect(decision.executed_at).to be_present
    
    # Execution record created correctly
    expect(execution.status).to eq('filled')
    expect(execution.alpaca_order_id).to eq('order-123')
    
    # Payloads stored
    expect(execution.api_request_payload).to be_present
    expect(execution.api_request_payload.endpoint).to eq('/v2/orders')
    expect(execution.api_response_payload).to be_present
    expect(execution.api_response_payload.payload['status']).to eq('filled')
    
    # Data Lineage preserved
    expect(decision.decision_rationale['data_lineage']).to be_present
  end
end
