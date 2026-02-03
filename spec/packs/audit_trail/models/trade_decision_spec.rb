# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditTrail::TradeDecision, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      decision = build(:trade_decision)
      expect(decision).to be_valid
    end

    it 'requires decision_id' do
      decision = build(:trade_decision, decision_id: nil)
      expect(decision).not_to be_valid
    end

    it 'requires strategy_name' do
      decision = build(:trade_decision, strategy_name: nil)
      expect(decision).not_to be_valid
    end

    it 'requires symbol' do
      decision = build(:trade_decision, symbol: nil)
      expect(decision).not_to be_valid
    end

    it 'validates symbol format' do
      decision = build(:trade_decision, symbol: 'invalid_symbol')
      expect(decision).not_to be_valid
    end

    it 'requires side' do
      decision = build(:trade_decision, side: nil)
      expect(decision).not_to be_valid
    end

    it 'validates side inclusion' do
      decision = build(:trade_decision, side: 'invalid')
      expect(decision).not_to be_valid
    end

    it 'requires quantity' do
      decision = build(:trade_decision, quantity: 0)
      expect(decision).not_to be_valid
    end

    it 'requires decision_rationale' do
      decision = build(:trade_decision, decision_rationale: nil)
      expect(decision).not_to be_valid
    end
  end

  describe 'state machine' do
    let(:decision) { create(:trade_decision, status: 'pending') }

    it 'starts in pending state' do
      expect(decision.status).to eq('pending')
    end

    it 'can transition from pending to executed' do
      expect { decision.execute }.to change(decision, :status).from('pending').to('executed')
    end

    it 'can transition from pending to failed' do
      expect { decision.fail }.to change(decision, :status).from('pending').to('failed')
    end

    it 'can transition from pending to cancelled' do
      expect { decision.cancel }.to change(decision, :status).from('pending').to('cancelled')
    end
  end

  describe 'helper methods' do
    let(:decision) { build(:trade_decision) }

    it '#signal_strength returns value from rationale' do
      expect(decision.signal_strength).to eq(8.5)
    end

    it '#confidence_score returns value from rationale' do
      expect(decision.confidence_score).to eq(0.85)
    end

    it '#trigger_event returns value from rationale' do
      expect(decision.trigger_event).to eq('congressional_buy')
    end

    it '#market_price_at_decision returns value from rationale' do
      expect(decision.market_price_at_decision).to eq(150.25)
    end
  end
end
