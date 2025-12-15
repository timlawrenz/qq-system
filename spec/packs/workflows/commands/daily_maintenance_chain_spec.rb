# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Workflows::DailyMaintenanceChain, type: :command do
  describe 'interface' do
    it 'is a chainable command' do
      expect(described_class.chain?).to be true
    end
  end

  describe '.call' do
    let(:fetch_result) do
      FetchInsiderTrades.build_context(
        total_count: 10,
        new_count: 4,
        updated_count: 1,
        error_count: 0,
        error_messages: []
      )
    end

    let(:cleanup_result) do
      Maintenance::CleanupBlockedAssets.build_context(removed_count: 3)
    end

    before do
      # Use RSpec's lower-level proxy API to avoid GLCommand matcher conflicts
      RSpec::Mocks.space.proxy_for(FetchInsiderTrades).add_stub(:call) { fetch_result }
      RSpec::Mocks.space.proxy_for(Maintenance::CleanupBlockedAssets).add_stub(:call) { cleanup_result }
    end

    it 'runs insider fetch and blocked asset cleanup in order' do
      result = described_class.call

      expect(result).to be_success

      returns = result.returns
      expect(returns[:total_count]).to eq(10)
      expect(returns[:new_count]).to eq(4)
      expect(returns[:updated_count]).to eq(1)
      expect(returns[:error_count]).to eq(0)
      expect(returns[:removed_count]).to eq(3)
    end
  end
end
