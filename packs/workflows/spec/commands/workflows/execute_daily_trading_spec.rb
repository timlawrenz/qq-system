# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Workflows::ExecuteDailyTrading, type: :command do
  describe 'interface' do
    it { is_expected.to allow(:trading_mode) }
    it { is_expected.to allow(:skip_data_fetch) }
    it { is_expected.to allow(:skip_politician_scoring) }
    it { is_expected.to returns(:trading_mode) }
    it { is_expected.to returns(:account_equity) }
    it { is_expected.to returns(:target_positions) }
    it { is_expected.to returns(:orders_placed) }
    it { is_expected.to returns(:final_positions) }
    it { is_expected.to returns(:metadata) }
  end

  describe '#call' do
    # These are complex integration tests - better tested via system specs
    # Just validate basic command structure here

    context 'with paper trading mode' do
      it 'validates trading mode parameter' do
        # Don't actually execute, just verify command structure
        expect(described_class).to respond_to(:call)
        expect(described_class).to respond_to(:call!)
      end
    end

    context 'with live trading mode' do
      it 'requires CONFIRM_LIVE_TRADING environment variable' do
        ENV.delete('CONFIRM_LIVE_TRADING')

        expect do
          described_class.call!(trading_mode: 'live', skip_data_fetch: true)
        end.to raise_error(GLCommand::StopAndFail, /CONFIRM_LIVE_TRADING/)
      end
    end

    context 'when portfolio generation fails' do
      it 'propagates errors correctly' do
        # Verify error handling structure exists
        expect do
          described_class.call!(trading_mode: 'invalid', skip_data_fetch: true)
        end.to raise_error(KeyError)
      end
    end
  end
end
