# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExecuteSimpleStrategyJob do
  describe '#perform' do
    context 'when both commands succeed' do
      let(:target_positions) do
        [
          TargetPosition.new(
            symbol: 'AAPL',
            asset_type: :stock,
            target_value: BigDecimal('5000.00')
          ),
          TargetPosition.new(
            symbol: 'GOOGL',
            asset_type: :stock,
            target_value: BigDecimal('5000.00')
          )
        ]
      end

      let(:mock_orders_placed) do
        [
          { id: 'order_1', symbol: 'AAPL', side: 'buy', status: 'submitted' },
          { id: 'order_2', symbol: 'GOOGL', side: 'buy', status: 'submitted' }
        ]
      end

      let(:mock_generate_result) do
        TradingStrategies::GenerateTargetPortfolio.build_context(target_positions: target_positions)
      end

      let(:mock_rebalance_result) do
        Trades::RebalanceToTarget.build_context(orders_placed: mock_orders_placed)
      end

      before do
        # Mock AlpacaService to prevent real API calls
        allow(AlpacaService).to receive(:new).and_return(instance_double(AlpacaService))

        # Mock the command calls
        allow(TradingStrategies::GenerateTargetPortfolio).to receive(:call).and_return(mock_generate_result)
        allow(Trades::RebalanceToTarget).to receive(:call).and_return(mock_rebalance_result)

        # Mock logging
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:error)
      end

      it 'enqueues and performs the job successfully' do
        expect { described_class.perform_now }.not_to raise_error
      end

      it 'calls GenerateTargetPortfolio command' do
        described_class.perform_now
        expect(TradingStrategies::GenerateTargetPortfolio).to have_received(:call)
      end

      it 'calls RebalanceToTarget with the target positions from GenerateTargetPortfolio' do
        described_class.perform_now
        expect(Trades::RebalanceToTarget).to have_received(:call).with(target: target_positions)
      end

      it 'calls commands in the correct order' do
        described_class.perform_now

        # Verify that GenerateTargetPortfolio is called before RebalanceToTarget
        expect(TradingStrategies::GenerateTargetPortfolio).to have_received(:call).ordered
        expect(Trades::RebalanceToTarget).to have_received(:call).with(target: target_positions).ordered
      end

      it 'logs successful execution with orders count' do
        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with(
          'ExecuteSimpleStrategyJob: Successfully executed simple strategy with 2 orders placed'
        )
      end
    end

    context 'when GenerateTargetPortfolio fails' do
      let(:mock_generate_result) do
        TradingStrategies::GenerateTargetPortfolio.build_context(error: 'Failed to fetch account equity')
      end

      before do
        # Mock AlpacaService to prevent real API calls
        allow(AlpacaService).to receive(:new).and_return(instance_double(AlpacaService))

        # Mock the failing command
        allow(TradingStrategies::GenerateTargetPortfolio).to receive(:call).and_return(mock_generate_result)
        allow(Trades::RebalanceToTarget).to receive(:call)

        # Mock logging
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the error and stops execution' do
        described_class.perform_now

        expect(Rails.logger).to have_received(:error).with(
          'ExecuteSimpleStrategyJob: GenerateTargetPortfolio failed: Failed to fetch account equity'
        )
      end

      it 'does not call RebalanceToTarget when GenerateTargetPortfolio fails' do
        described_class.perform_now
        expect(Trades::RebalanceToTarget).not_to have_received(:call)
      end
    end

    context 'when RebalanceToTarget fails' do
      let(:target_positions) do
        [
          TargetPosition.new(
            symbol: 'AAPL',
            asset_type: :stock,
            target_value: BigDecimal('5000.00')
          )
        ]
      end

      let(:mock_generate_result) do
        TradingStrategies::GenerateTargetPortfolio.build_context(target_positions: target_positions)
      end

      let(:mock_rebalance_result) do
        Trades::RebalanceToTarget.build_context(error: 'Failed to place order')
      end

      before do
        # Mock AlpacaService to prevent real API calls
        allow(AlpacaService).to receive(:new).and_return(instance_double(AlpacaService))

        # Mock the commands
        allow(TradingStrategies::GenerateTargetPortfolio).to receive(:call).and_return(mock_generate_result)
        allow(Trades::RebalanceToTarget).to receive(:call).and_return(mock_rebalance_result)

        # Mock logging
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the rebalance error' do
        described_class.perform_now

        expect(Rails.logger).to have_received(:error).with(
          'ExecuteSimpleStrategyJob: RebalanceToTarget failed: Failed to place order'
        )
      end

      it 'still calls both commands in order even when rebalance fails' do
        described_class.perform_now

        expect(TradingStrategies::GenerateTargetPortfolio).to have_received(:call).ordered
        expect(Trades::RebalanceToTarget).to have_received(:call).with(target: target_positions).ordered
      end
    end

    context 'when an unexpected error occurs' do
      before do
        # Mock AlpacaService to prevent real API calls
        allow(AlpacaService).to receive(:new).and_return(instance_double(AlpacaService))

        # Mock GenerateTargetPortfolio to raise an unexpected error
        allow(TradingStrategies::GenerateTargetPortfolio).to receive(:call).and_raise(StandardError, 'Unexpected error')

        # Mock logging
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the error details and re-raises the exception' do
        expect { described_class.perform_now }.to raise_error(StandardError, 'Unexpected error')

        expect(Rails.logger).to have_received(:error).with(
          'ExecuteSimpleStrategyJob: Unexpected error: Unexpected error'
        )
        expect(Rails.logger).to have_received(:error).at_least(:once) # backtrace can be multiple lines
      end
    end

    context 'with empty target portfolio' do
      let(:target_positions) { [] }

      let(:mock_generate_result) do
        TradingStrategies::GenerateTargetPortfolio.build_context(target_positions: target_positions)
      end

      let(:mock_rebalance_result) do
        Trades::RebalanceToTarget.build_context(orders_placed: [])
      end

      before do
        # Mock AlpacaService to prevent real API calls
        allow(AlpacaService).to receive(:new).and_return(instance_double(AlpacaService))

        # Mock the command calls
        allow(TradingStrategies::GenerateTargetPortfolio).to receive(:call).and_return(mock_generate_result)
        allow(Trades::RebalanceToTarget).to receive(:call).and_return(mock_rebalance_result)

        # Mock logging
        allow(Rails.logger).to receive(:info)
      end

      it 'handles empty portfolio gracefully' do
        described_class.perform_now

        expect(TradingStrategies::GenerateTargetPortfolio).to have_received(:call)
        expect(Trades::RebalanceToTarget).to have_received(:call).with(target: [])
        expect(Rails.logger).to have_received(:info).with(
          'ExecuteSimpleStrategyJob: Successfully executed simple strategy with 0 orders placed'
        )
      end
    end
  end
end
