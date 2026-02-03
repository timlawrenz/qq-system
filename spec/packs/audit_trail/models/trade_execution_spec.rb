# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditTrail::TradeExecution, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      execution = build(:trade_execution)
      expect(execution).to be_valid
    end

    it 'requires execution_id' do
      execution = build(:trade_execution, execution_id: nil)
      expect(execution).not_to be_valid
    end

    it 'requires status' do
      execution = build(:trade_execution, status: nil)
      expect(execution).not_to be_valid
    end

    it 'validates status inclusion' do
      execution = build(:trade_execution, status: 'invalid')
      expect(execution).not_to be_valid
    end
  end

  describe 'helper methods' do
    it '#success? returns true for filled status' do
      execution = build(:trade_execution, status: 'filled')
      expect(execution.success?).to be true
    end

    it '#failure? returns true for rejected status' do
      execution = build(:trade_execution, status: 'rejected')
      expect(execution.failure?).to be true
    end
  end
end
