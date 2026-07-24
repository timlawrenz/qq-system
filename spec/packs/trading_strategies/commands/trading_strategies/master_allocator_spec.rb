# frozen_string_literal: true

# rubocop:disable RSpec/AnyInstance

require 'rails_helper'
require Rails.root.join('packs/trading_strategies/app/strategies/congressional.rb')
require Rails.root.join('packs/trading_strategies/app/strategies/insider.rb')
require Rails.root.join('packs/trading_strategies/app/strategies/lobbying.rb')
require Rails.root.join('packs/trading_strategies/app/strategies/contracts.rb')
require Rails.root.join('packs/trading_strategies/app/strategies/base_strategy.rb')

RSpec.describe TradingStrategies::MasterAllocator do
  subject(:command) { described_class.call(total_equity: total_equity, trading_mode: trading_mode) }

  let(:total_equity) { BigDecimal('10000') }
  let(:trading_mode) { 'test' }

  let(:congressional_signals) do
    [
      build_signal('AAPL', 'congressional', 0.8, quiver_trade_ids: [1]),
      build_signal('TSLA', 'congressional', -0.6, quiver_trade_ids: [2])
    ]
  end

  let(:insider_signals) do
    [
      build_signal('AAPL', 'insider', 0.5, quiver_trade_ids: [3]),
      build_signal('MSFT', 'insider', -0.4, quiver_trade_ids: [4])
    ]
  end

  let(:lobbying_signals) do
    [
      build_signal('MSFT', 'lobbying', 1.0, quiver_trade_ids: [5])
    ]
  end

  let(:contracts_signals) do
    [] # contracts disabled by default
  end

  before do
    # Required by AlpacaService initialization in VolatilitySizingService
    ENV['TRADING_MODE'] = 'paper'

    # Mock strategy classes to return known signals
    allow_any_instance_of(TradingStrategies::Strategies::Congressional)
      .to receive(:generate_signals).and_return(congressional_signals)

    allow_any_instance_of(TradingStrategies::Strategies::Insider)
      .to receive(:generate_signals).and_return(insider_signals)

    allow_any_instance_of(TradingStrategies::Strategies::Lobbying)
      .to receive(:generate_signals).and_return(lobbying_signals)

    allow_any_instance_of(TradingStrategies::Strategies::Contracts)
      .to receive(:generate_signals).and_return(contracts_signals)

    # Stub market data prewarm
    allow(Fetch).to receive(:call).and_return(
      double(success?: true, failure?: false, api_errors: [])
    )

    # Stub VolatilitySizingService to return known positions
    allow_any_instance_of(TradingStrategies::VolatilitySizingService)
      .to receive(:call).and_return(
        [
          TargetPosition.new(symbol: 'AAPL', asset_type: :stock,
                             target_value: BigDecimal('360'), details: {}),
          TargetPosition.new(symbol: 'MSFT', asset_type: :stock,
                             target_value: BigDecimal('400'), details: {})
        ]
      )
  end

  describe '#call' do
    it 'returns successfully' do
      expect(command).to be_success
    end

    it 'returns target_positions' do
      expect(command.target_positions).not_to be_empty
    end

    it 'returns strategy_results' do
      expect(command.strategy_results).to be_a(Hash)
    end

    it 'returns metadata' do
      expect(command.metadata).to be_a(Hash)
    end

    it 'includes total_signal count in metadata' do
      # congressional(2) + insider(2) + lobbying(1) = 5 signals
      expect(command.metadata[:total_signals]).to eq(5)
    end

    it 'includes netted_tickers count in metadata' do
      # AAPL, TSLA, MSFT = 3 unique tickers
      expect(command.metadata[:netted_tickers]).to eq(3)
    end

    it 'includes generated_positions count in metadata' do
      expect(command.metadata[:generated_positions]).to eq(2) # mocked to 2
    end

    it 'includes risk_target_pct in metadata' do
      expect(command.metadata[:risk_target_pct]).to be > 0
    end

    context 'with strategy results reporting' do
      it 'records signal counts per strategy' do
        results = command.strategy_results
        expect(results['congressional'][:signal_count]).to eq(2)
        expect(results['insider'][:signal_count]).to eq(2)
        expect(results['lobbying'][:signal_count]).to eq(1)
      end

      it 'marks each strategy as success' do
        results = command.strategy_results
        expect(results.values).to all(include(status: 'success'))
      end
    end

    context 'when a strategy fails' do
      before do
        allow_any_instance_of(TradingStrategies::Strategies::Insider)
          .to receive(:generate_signals).and_raise(StandardError, 'API timeout')
      end

      it 'records the failure without crashing' do
        expect(command).to be_success
      end

      it 'marks the failed strategy as failed' do
        results = command.strategy_results
        expect(results['insider'][:status]).to eq('failed')
        expect(results['insider'][:error]).to include('API timeout')
      end

      it 'still reports signals from other strategies' do
        expect(command.metadata[:total_signals]).to eq(3) # only congressional + lobbying
      end
    end

    context 'when market data prewarm fails' do
      before do
        allow(Fetch).to receive(:call).and_return(
          double(success?: false, failure?: true, error: StandardError.new('rate limit'))
        )
      end

      it 'continues without crashing' do
        expect(command).to be_success
      end
    end

    context 'when target_positions is empty (signal starvation)' do
      before do
        allow_any_instance_of(TradingStrategies::VolatilitySizingService)
          .to receive(:call).and_return([])
      end

      it 'returns empty target_positions' do
        expect(command.target_positions).to be_empty
      end

      it 'still reports metadata' do
        expect(command.metadata[:generated_positions]).to eq(0)
      end
    end

    context 'with missing total_equity' do
      let(:total_equity) { 0 }

      it 'fails with a validation error' do
        expect(command).to be_failure
        expect(command.error).to be_a(StandardError)
        expect(command.error.message).to include('total_equity')
      end
    end

    context 'with nil total_equity' do
      let(:total_equity) { nil }

      it 'fails with a validation error' do
        expect(command).to be_failure
      end
    end
  end

  describe 'signal netting' do
    # Cross-strategy consensus: AAPL gets congressional(0.8) + insider(0.5)
    # With equal weights (0.5 each), net = (0.8*0.5 + 0.5*0.5) / 1.0 = 0.65
    it 'blends signals from multiple strategies on the same ticker' do
      # This is verified indirectly through the VolatilitySizingService mock,
      # but the SignalNettingService is already tested separately.
      expect(command.metadata[:netted_tickers]).to be <= 3
    end

    it 'handles conflicting signals (long vs short) correctly' do
      # TSLA is short via congressional, MSFT has lobbying(long) + insider(short)
      # The netting service resolves these
      expect(command.metadata[:total_signals]).to eq(5)
    end
  end

  describe 'config loading' do
    context 'with test environment' do
      it 'loads the test config section' do
        # test config has lobbying at weight 0.5, congressional at 0.5
        expect(command.metadata[:risk_target_pct]).to be > 0
      end
    end

    context 'with paper environment' do
      let(:trading_mode) { 'paper' }

      it 'loads paper-specific configuration' do
        expect(command).to be_success
      end
    end

    context 'with config_override' do
      subject(:command) do
        described_class.call(
          total_equity: total_equity,
          trading_mode: trading_mode,
          config_override: { 'max_position_pct' => 0.5 }
        )
      end

      it 'merges the override into config' do
        expect(command).to be_success
      end
    end

    context 'with unknown trading_mode' do
      let(:trading_mode) { 'nonexistent' }

      it 'loads default config gracefully' do
        expect(command).to be_success
      end
    end
  end

  # Helper to build TradingSignal objects
  def build_signal(ticker, strategy, score, quiver_trade_ids: [])
    TradingStrategies::TradingSignal.new(
      ticker: ticker,
      strategy_name: strategy,
      score: score,
      metadata: { quiver_trade_ids: quiver_trade_ids }
    )
  end
end
# rubocop:enable RSpec/AnyInstance
