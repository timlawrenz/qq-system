# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DeleteTrade, type: :command do
  let(:algorithm) { create(:algorithm) }
  let(:trade) { create(:trade, algorithm: algorithm) }

  describe 'successful deletion' do
    it 'deletes the trade' do
      trade_id = trade.id
      result = described_class.call(trade: trade)

      expect(result).to be_success
      expect(result.trade).to eq(trade)
      expect { Trade.find(trade_id) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'returns the deleted trade object' do
      result = described_class.call(trade: trade)

      expect(result).to be_success
      expect(result.trade).to eq(trade)
      expect(result.trade).to be_destroyed
    end
  end

  describe 'validation failures' do
    it 'fails when trade is missing' do
      result = described_class.call

      expect(result).to be_failure
    end
  end
end
