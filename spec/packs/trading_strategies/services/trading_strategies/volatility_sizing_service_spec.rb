# frozen_string_literal: true

# rubocop:disable RSpec/AnyInstance
# Many stubs use allow_any_instance_of to mock private helper methods
# (calculate_atr, fetch_current_price, fetch_bars_for_atr) since the service
# creates its own AlpacaService internally and we test sizing logic in isolation.

require 'rails_helper'

RSpec.describe TradingStrategies::VolatilitySizingService do
  subject(:service) do
    described_class.new(
      net_results: net_results,
      total_equity: total_equity,
      risk_target_pct: risk_target_pct
    )
  end

  let(:total_equity) { BigDecimal('10000') }
  let(:risk_target_pct) { 0.01 } # 1% per trade

  let(:net_results) do
    {
      'AAPL' => { score: 0.6, signals: [build_signal('AAPL', 'congressional', 0.6)] },
      'MSFT' => { score: -0.4, signals: [build_signal('MSFT', 'congressional', -0.4)] }
    }
  end

  let(:mock_current_prices) do
    { 'AAPL' => BigDecimal('180'), 'MSFT' => BigDecimal('400') }
  end

  let(:mock_bars) do
    # 15 days of bars for ATR calculation
    (0..16).map do |i|
      {
        timestamp: (16 - i).days.ago.to_date,
        open: BigDecimal('175'),
        high: BigDecimal((180 + rand).to_s),
        low: BigDecimal((172 + rand).to_s),
        close: BigDecimal((177 + rand).to_s),
        volume: 10_000_000
      }
    end
  end

  before do
    # Stub AlpacaService
    alpaca = instance_double(AlpacaService)
    allow(alpaca).to receive_messages(get_bars: mock_bars, get_bars_multi: { 'AAPL' => mock_bars,
                                                                             'MSFT' => mock_bars })

    allow(AlpacaService).to receive(:new).and_return(alpaca)

    # Stub HistoricalBar to return empty (force API fallback)
    empty_relation = instance_double(ActiveRecord::Relation, to_a: [])
    chained_relation = instance_double(ActiveRecord::Relation)
    allow(chained_relation).to receive(:where).and_return(chained_relation)
    allow(chained_relation).to receive(:order).and_return(chained_relation)
    allow(chained_relation).to receive(:to_a).and_return([])
    allow(HistoricalBar).to receive(:for_symbol).and_return(chained_relation)
  end

  describe '#call' do
    context 'with valid inputs' do
      before do
        # Stub current prices from batch prefetch
        allow_any_instance_of(described_class).to receive(:fetch_current_price)
          .with('AAPL').and_return(BigDecimal('180'))
        allow_any_instance_of(described_class).to receive(:fetch_current_price)
          .with('MSFT').and_return(BigDecimal('400'))
      end

      it 'returns TargetPosition objects' do
        result = service.call
        expect(result).to all(be_a(TargetPosition))
      end

      it 'creates positions for all valid tickers' do
        result = service.call
        symbols = result.map(&:symbol)
        expect(symbols).to contain_exactly('AAPL', 'MSFT')
      end

      it 'sets asset_type to :stock' do
        result = service.call
        expect(result.map(&:asset_type)).to all(eq(:stock))
      end

      it 'positive scores produce positive target values' do
        result = service.call
        aapl = result.find { |p| p.symbol == 'AAPL' }
        expect(aapl.target_value).to be_positive
      end

      it 'negative scores produce negative target values' do
        result = service.call
        msft = result.find { |p| p.symbol == 'MSFT' }
        expect(msft.target_value).to be_negative
      end

      it 'includes signal metadata in details' do
        result = service.call
        aapl = result.find { |p| p.symbol == 'AAPL' }
        expect(aapl.details[:net_score]).to eq(0.6)
        expect(aapl.details[:atr]).to be > 0
        expect(aapl.details[:sources]).to include('congressional')
      end
    end

    context 'when ATR is unavailable and price fetch also fails' do
      before do
        # Make calculate_atr go through the full path and fail
        allow_any_instance_of(described_class).to receive(:fetch_bars_for_atr).and_return([])
        allow_any_instance_of(described_class).to receive(:fetch_current_price).and_return(nil)
      end

      it 'blocks the asset and skips the position' do
        expect(BlockedAsset).to receive(:block_asset)
          .with(symbol: anything, reason: 'market_data_unavailable').twice
        result = service.call
        expect(result).to be_empty
      end
    end

    context 'when score is zero' do
      let(:net_results) do
        { 'AAPL' => { score: 0.0, signals: [] } }
      end

      it 'skips the ticker entirely' do
        result = service.call
        expect(result).to be_empty
      end
    end

    context 'with invalid ticker symbols' do
      let(:net_results) do
        {
          'TOOLONG' => { score: 0.5, signals: [build_signal('TOOLONG', 'c', 0.5)] },
          '123' => { score: 0.5, signals: [build_signal('123', 'c', 0.5)] },
          'AAPL' => { score: 0.5, signals: [build_signal('AAPL', 'c', 0.5)] }
        }
      end

      before do
        allow_any_instance_of(described_class).to receive(:fetch_current_price)
          .and_return(BigDecimal('100'))
      end

      it 'filters out non-standard tickers (>5 chars, non-letters)' do
        result = service.call
        symbols = result.map(&:symbol)
        expect(symbols).to eq(['AAPL'])
      end
    end

    context 'when ATR is zero (should not happen normally)' do
      before do
        allow_any_instance_of(described_class).to receive(:calculate_atr).and_return(0.0)
      end

      it 'skips the position without blocking' do
        result = service.call
        expect(result).to be_empty
      end
    end

    context 'when current price is nil' do
      before do
        allow_any_instance_of(described_class).to receive(:calculate_atr).and_return(3.0)
        allow_any_instance_of(described_class).to receive(:fetch_current_price).and_return(nil)
      end

      it 'skips the position' do
        result = service.call
        expect(result).to be_empty
      end
    end

    context 'with multiple signals per ticker (cross-strategy consensus)' do
      let(:net_results) do
        {
          'AAPL' => {
            score: 0.8,
            signals: [
              build_signal('AAPL', 'congressional', 0.6, quiver_trade_ids: [1]),
              build_signal('AAPL', 'insider', 1.0, quiver_trade_ids: [2])
            ]
          }
        }
      end

      before do
        allow_any_instance_of(described_class).to receive(:calculate_atr).and_return(3.0)
        allow_any_instance_of(described_class).to receive(:fetch_current_price)
          .with('AAPL').and_return(BigDecimal('180'))
      end

      it 'combines quiver_trade_ids from all signals' do
        result = service.call
        expect(result.first.details[:quiver_trade_ids]).to contain_exactly(1, 2)
      end

      it 'combines source strategy names' do
        result = service.call
        expect(result.first.details[:sources]).to contain_exactly('congressional', 'insider')
      end
    end

    context 'with sizing formula verification' do
      # The formula: shares = equity * risk_pct / ATR
      #              adj_shares = shares * score.abs
      #              target_value = adj_shares * price
      before do
        allow_any_instance_of(described_class).to receive(:calculate_atr).and_return(BigDecimal('3'))
        allow_any_instance_of(described_class).to receive(:fetch_current_price)
          .with('AAPL').and_return(BigDecimal('180'))
      end

      let(:net_results) do
        { 'AAPL' => { score: 0.6, signals: [build_signal('AAPL', 'c', 0.6)] } }
      end

      it 'calculates target_value from the sizing formula (no floor loss)' do
        result = service.call
        position = result.first

        # risk_amount = 10000 * 0.01 = 100
        # shares = 100 / 3 = 33.333...
        # adj_shares = 33.333... * 0.6 = 20.0
        # target_value = 20.0 * 180 = 3600
        expect(position.target_value).to be_within(0.01).of(BigDecimal('3600'))
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
