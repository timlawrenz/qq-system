# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditTrail::CreateTradeDecision, type: :command do
  describe '.call' do
    let(:strategy_name) { 'CongressionalTradingStrategy' }
    let(:symbol) { 'AAPL' }
    let(:side) { 'buy' }
    let(:quantity) { 100 }
    let(:rationale) { { signal_strength: 9.0 } }

    it 'creates a TradeDecision record with pending status' do
      expect do
        described_class.call(
          strategy_name: strategy_name,
          symbol: symbol,
          side: side,
          quantity: quantity,
          rationale: rationale
        )
      end.to change(AuditTrail::TradeDecision, :count).by(1)

      decision = AuditTrail::TradeDecision.last
      expect(decision.status).to eq('pending')
      expect(decision.symbol).to eq('AAPL')
      expect(decision.side).to eq('buy')
      expect(decision.quantity).to eq(100)
    end

    it 'links to recent successful ingestion runs' do
      run = create(:data_ingestion_run, :completed, completed_at: 1.hour.ago)

      result = described_class.call(
        strategy_name: strategy_name,
        symbol: symbol,
        side: side,
        quantity: quantity,
        rationale: rationale
      )

      decision = result.trade_decision
      expect(decision.primary_ingestion_run).to eq(run)
      expect(decision.decision_rationale['data_lineage']['ingestion_runs']).not_to be_empty
      expect(decision.decision_rationale['data_lineage']['ingestion_runs'].first['run_id']).to eq(run.run_id)
    end

    it 'links to primary_quiver_trade_id when provided' do
      qt = create(:quiver_trade)

      result = described_class.call(
        strategy_name: strategy_name,
        symbol: symbol,
        side: side,
        quantity: quantity,
        primary_quiver_trade_id: qt.id
      )

      expect(result.trade_decision.primary_quiver_trade).to eq(qt)
    end
  end
end
