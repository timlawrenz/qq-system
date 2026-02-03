# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingStrategies::GenerateInsiderMimicryPortfolio, type: :command do
  describe 'interface' do
    it { is_expected.to allow(:lookback_days) }
    it { is_expected.to allow(:min_transaction_value) }
    it { is_expected.to allow(:executive_only) }
    it { is_expected.to allow(:position_size_weight_by_value) }
    it { is_expected.to allow(:total_equity) }
    it { is_expected.to allow(:max_positions) }
    it { is_expected.to allow(:sizing_mode) }
    it { is_expected.to allow(:role_weights) }
    it { is_expected.to returns(:target_positions) }
    it { is_expected.to returns(:total_value) }
    it { is_expected.to returns(:filters_applied) }
    it { is_expected.to returns(:stats) }
  end

  describe '#call' do
    let(:total_equity) { BigDecimal('100000.00') }
    let(:allocated_equity) { BigDecimal('20000.00') } # 20% allocation

    before do
      # Clean slate for each test
      QuiverTrade.where(trader_source: 'insider').delete_all
    end

    context 'with max_positions limit' do
      before do
        # Create realistic insider trades for this test only
        50.times do |i|
          create(:quiver_trade,
                 trader_source: 'insider',
                 transaction_type: 'Purchase',
                 transaction_date: (i % 30).days.ago,
                 trade_size_usd: "$#{rand(10_000..100_000).to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}",
                 relationship: i.even? ? 'CEO' : 'CFO',
                 ticker: "TICK#{i}")
        end
      end

      it 'limits to top 20 positions by weight' do
        result = described_class.call(
          total_equity: allocated_equity,
          max_positions: 20,
          lookback_days: 30,
          min_transaction_value: 10_000,
          executive_only: true
        )

        expect(result).to be_success
        expect(result.target_positions.size).to eq(20)
        expect(result.stats[:tickers_before_limit]).to be >= 20
        expect(result.stats[:tickers_after_limit]).to eq(20)
      end

      it 'allocates proper position sizes (no positions below $500)' do
        result = described_class.call(
          total_equity: allocated_equity,
          max_positions: 20,
          min_transaction_value: 10_000
        )

        expect(result).to be_success

        # With $20k equity and 20 positions, average should be ~$1,000
        avg_position_size = allocated_equity / 20
        expect(avg_position_size).to be > 500 # Above minimum

        # Check all positions are reasonable size
        result.target_positions.each do |pos|
          expect(pos.target_value).to be > 500, "Position #{pos.symbol} too small: $#{pos.target_value}"
        end

        # Total should equal allocated equity
        total_value = result.target_positions.sum(&:target_value)
        expect(total_value).to be_within(1).of(allocated_equity)
      end
    end

    context 'with 435 tickers (production bug scenario)' do
      before do
        # Create 435 insider trades (matches production)
        385.times do |i|
          create(:quiver_trade,
                 trader_source: 'insider',
                 transaction_type: 'Purchase',
                 transaction_date: rand(30).days.ago,
                 trade_size_usd: "$#{rand(10_000..60_000).to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}",
                 relationship: 'CEO',
                 ticker: "PROD#{i}")
        end
      end

      it 'does not create 95 tiny positions' do
        # This tests the bug we found: 95 positions at $214 each
        result = described_class.call(
          total_equity: BigDecimal('20348.00'), # 20% of $101,817
          max_positions: 20
        )

        expect(result).to be_success

        # Should create exactly 20 positions (not 95!)
        expect(result.target_positions.size).to eq(20)

        # Average position should be ~$1,017 (not $214!)
        avg_size = BigDecimal('20348.00') / 20
        expect(avg_size).to be > 1000

        # No position should be below $500
        result.target_positions.each do |pos|
          expect(pos.target_value).to be >= 500,
                                      "Position #{pos.symbol} is #{pos.target_value}, should be >= 500"
        end

        # Total allocation should be utilized
        total_value = result.target_positions.sum(&:target_value)
        utilization = (total_value / BigDecimal('20348.00') * 100).round(1)
        expect(utilization).to be >= 95.0 # At least 95% utilization
      end
    end

    context 'with weight-based position sizing' do
      before do
        # Clean and create ONLY these two trades
        QuiverTrade.where(trader_source: 'insider').delete_all

        # Create trades with varying sizes
        create(:quiver_trade,
               ticker: 'LARGE',
               trader_source: 'insider',
               transaction_type: 'Purchase',
               trade_size_usd: '$1,000,000',
               relationship: 'CEO',
               transaction_date: 5.days.ago)

        create(:quiver_trade,
               ticker: 'SMALL',
               trader_source: 'insider',
               transaction_type: 'Purchase',
               trade_size_usd: '$10,000',
               relationship: 'CEO',
               transaction_date: 5.days.ago)
      end

      context 'with equal-weight sizing mode' do
        before do
          QuiverTrade.where(trader_source: 'insider').delete_all

          create(:quiver_trade,
                 ticker: 'AAA',
                 trader_source: 'insider',
                 transaction_type: 'Purchase',
                 trade_size_usd: '$10,000',
                 relationship: 'CEO',
                 transaction_date: 5.days.ago)

          create(:quiver_trade,
                 ticker: 'BBB',
                 trader_source: 'insider',
                 transaction_type: 'Purchase',
                 trade_size_usd: '$50,000',
                 relationship: 'CFO',
                 transaction_date: 5.days.ago)
        end

        it 'allocates approximately equal dollar amounts per ticker' do
          result = described_class.call(
            total_equity: BigDecimal('10000.00'),
            sizing_mode: 'equal_weight',
            max_positions: 20
          )

          expect(result).to be_success
          expect(result.target_positions.size).to eq(2)

          a_pos = result.target_positions.find { |p| p.symbol == 'AAA' }
          b_pos = result.target_positions.find { |p| p.symbol == 'BBB' }

          expect(a_pos).not_to be_nil
          expect(b_pos).not_to be_nil
          expect(a_pos.target_value).to be_within(50).of(b_pos.target_value)
        end
      end

      context 'with role-weighted sizing mode' do
        before do
          QuiverTrade.where(trader_source: 'insider').delete_all

          # CEO + CFO both buying the same stock
          create(:quiver_trade,
                 ticker: 'DUAL',
                 trader_source: 'insider',
                 transaction_type: 'Purchase',
                 trade_size_usd: '$20,000',
                 relationship: 'CEO',
                 transaction_date: 5.days.ago)

          create(:quiver_trade,
                 ticker: 'DUAL',
                 trader_source: 'insider',
                 transaction_type: 'Purchase',
                 trade_size_usd: '$20,000',
                 relationship: 'CFO',
                 transaction_date: 5.days.ago)

          # Single Director trade in another stock
          create(:quiver_trade,
                 ticker: 'SOLO',
                 trader_source: 'insider',
                 transaction_type: 'Purchase',
                 trade_size_usd: '$20,000',
                 relationship: 'Director',
                 transaction_date: 5.days.ago)
        end

        it 'sums role weights per ticker and normalizes allocations' do
          result = described_class.call(
            total_equity: BigDecimal('10000.00'),
            sizing_mode: 'role_weighted',
            max_positions: 20,
            executive_only: false
          )

          expect(result).to be_success
          expect(result.target_positions.size).to eq(2)

          dual = result.target_positions.find { |p| p.symbol == 'DUAL' }
          solo = result.target_positions.find { |p| p.symbol == 'SOLO' }

          expect(dual).not_to be_nil
          expect(solo).not_to be_nil

          # With defaults CEO=2.0, CFO=1.5, Director=1.0 -> DUAL=3.5, SOLO=1.0
          # DUAL should get more than 3x SOLO allocation after normalization
          expect(dual.target_value).to be > solo.target_value * 3

          total = result.target_positions.sum(&:target_value)
          expect(total).to be_within(1).of(BigDecimal('10000.00'))
        end
      end

      it 'allocates more to higher-value trades' do
        result = described_class.call(
          total_equity: BigDecimal('10000.00'),
          position_size_weight_by_value: true,
          max_positions: 20
        )

        expect(result).to be_success
        expect(result.target_positions.size).to eq(2)

        large_pos = result.target_positions.find { |p| p.symbol == 'LARGE' }
        small_pos = result.target_positions.find { |p| p.symbol == 'SMALL' }

        expect(large_pos).not_to be_nil, "LARGE position not found in #{result.target_positions.map(&:symbol)}"
        expect(small_pos).not_to be_nil, "SMALL position not found in #{result.target_positions.map(&:symbol)}"

        # LARGE should get much more allocation than SMALL (~100x the trade value)
        expect(large_pos.target_value).to be > small_pos.target_value * 10
      end
    end

    context 'with executive_only filter' do
      before do
        # Clean and create ONLY these test trades
        QuiverTrade.where(trader_source: 'insider').delete_all

        create(:quiver_trade,
               ticker: 'EXEC',
               trader_source: 'insider',
               transaction_type: 'Purchase',
               relationship: 'CEO',
               trade_size_usd: '$50,000',
               transaction_date: 5.days.ago)

        create(:quiver_trade,
               ticker: 'NONEXEC',
               trader_source: 'insider',
               transaction_type: 'Purchase',
               relationship: 'Director',
               trade_size_usd: '$50,000',
               transaction_date: 5.days.ago)
      end

      it 'includes only executive trades' do
        result = described_class.call(
          total_equity: BigDecimal('10000.00'),
          executive_only: true,
          max_positions: 20
        )

        expect(result).to be_success
        expect(result.target_positions.size).to eq(1),
                                                "Expected 1 position, got #{result.target_positions.size}: " \
                                                "#{result.target_positions.map(&:symbol)}"

        symbols = result.target_positions.map(&:symbol)
        expect(symbols).to include('EXEC')
        expect(symbols).not_to include('NONEXEC')
      end
    end

    context 'with no trades' do
      before do
        QuiverTrade.where(trader_source: 'insider').delete_all
      end

      it 'returns empty portfolio' do
        result = described_class.call(total_equity: BigDecimal('10000.00'))

        expect(result).to be_success
        expect(result.target_positions).to be_empty
      end
    end
  end
end
