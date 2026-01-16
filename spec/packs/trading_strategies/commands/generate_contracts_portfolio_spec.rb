# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingStrategies::GenerateContractsPortfolio do
  let(:total_equity) { 100_000.0 }

  def create_contract(attrs = {})
    GovernmentContract.create!(
      {
        contract_id: SecureRandom.hex(6),
        ticker: 'LMT',
        company: 'Lockheed Martin',
        contract_value: 50_000_000,
        award_date: 2.days.ago.to_date,
        agency: 'Department of Defense',
        contract_type: 'Services',
        description: 'Test contract'
      }.merge(attrs)
    )
  end

  before do
    # Keep tests deterministic and avoid cache bleed
    Rails.cache.clear

    allow(TradingStrategies::FundamentalDataService).to receive(:get_annual_revenue).and_call_original
  end

  describe '.call' do
    it 'returns empty portfolio when no contracts qualify' do
      create_contract(ticker: 'UNKNOWN', contract_value: 1_000_000)
      allow(TradingStrategies::FundamentalDataService)
        .to receive(:get_annual_revenue)
        .with('UNKNOWN')
        .and_return(BigDecimal('1000000000000'))

      result = described_class.call(
        total_equity: total_equity,
        min_contract_value: 10_000_000,
        min_materiality_pct: 5.0
      )

      expect(result).to be_success
      expect(result.target_positions).to eq([])
    end

    it 'equal-weights qualifying contracts across tickers' do
      create_contract(ticker: 'LMT', contract_value: 50_000_000)
      create_contract(ticker: 'NOC', contract_value: 50_000_000)

      allow(TradingStrategies::FundamentalDataService)
        .to receive(:get_annual_revenue)
        .with('LMT')
        .and_return(BigDecimal('1000000000'))
      allow(TradingStrategies::FundamentalDataService)
        .to receive(:get_annual_revenue)
        .with('NOC')
        .and_return(BigDecimal('1000000000'))

      result = described_class.call(
        total_equity: total_equity,
        sizing_mode: 'equal_weight',
        min_contract_value: 10_000_000,
        min_materiality_pct: 1.0
      )

      expect(result).to be_success
      symbols = result.target_positions.map(&:symbol)
      expect(symbols).to contain_exactly('LMT', 'NOC')

      values = result.target_positions.map(&:target_value)
      expect(values.uniq.size).to eq(1)
      expect(values.first).to be_within(0.01).of(50_000.0)
    end

    it 'includes contracts with missing revenue data by default' do
      create_contract(ticker: 'MYST', contract_value: 50_000_000)
      allow(TradingStrategies::FundamentalDataService).to receive(:get_annual_revenue).with('MYST').and_return(nil)

      result = described_class.call(
        total_equity: total_equity,
        min_contract_value: 10_000_000,
        min_materiality_pct: 10.0
      )

      expect(result).to be_success
      expect(result.target_positions.map(&:symbol)).to contain_exactly('MYST')
    end

    it 'fails when total_equity is missing' do
      result = described_class.call(total_equity: nil)
      expect(result).to be_failure
      expect(result.full_error_message).to include('total_equity parameter is required and must be positive')
    end

    it 'includes QuarterlyTotal contracts updated recently even if award_date is in future' do
      c = create_contract(
        ticker: 'QTR',
        contract_value: 50_000_000,
        contract_type: 'QuarterlyTotal',
        award_date: 3.months.from_now.to_date
      )
      c.update_columns(updated_at: 1.day.ago)

      allow(TradingStrategies::FundamentalDataService)
        .to receive(:get_annual_revenue)
        .with('QTR')
        .and_return(BigDecimal('1000000000'))

      result = described_class.call(
        total_equity: total_equity,
        lookback_days: 7,
        holding_period_days: 10,
        min_contract_value: 10_000_000,
        min_materiality_pct: 1.0
      )

      expect(result).to be_success
      expect(result.target_positions.map(&:symbol)).to contain_exactly('QTR')
    end
  end
end
