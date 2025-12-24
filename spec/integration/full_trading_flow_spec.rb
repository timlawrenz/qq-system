# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Full Trading Flow with Audit Trail' do
  let(:symbol) { 'AAPL' }

  before do
    # 0. Setup Politician Profile for Nancy Pelosi (so she passes filters)
    PoliticianProfile.create!(
      name: 'Nancy Pelosi',
      quality_score: 9.5,
      party: 'Democrat'
    )

    # 1. Mock QuiverQuant API
    client_double = instance_double(QuiverClient)
    allow(QuiverClient).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:fetch_congressional_trades).and_return([
      {
        ticker: symbol,
        company: 'Apple Inc.',
        trader_name: 'Nancy Pelosi',
        transaction_date: Date.current,
        transaction_type: 'Purchase',
        trade_size_usd: '100000-250000',
        filed: Time.current.to_s
      }
    ])
    allow(client_double).to receive(:api_calls).and_return([
      { 
        endpoint: '/bulk/congresstrading', 
        status_code: 200,
        request: { endpoint: '/bulk/congresstrading', method: 'GET' },
        response: { status_code: 200 }
      }
    ])

    # 2. Mock Alpaca API
    alpaca_double = instance_double(AlpacaService)
    allow(AlpacaService).to receive(:new).and_return(alpaca_double)
    allow(alpaca_double).to receive(:account_equity).and_return(BigDecimal('100000'))
    allow(alpaca_double).to receive(:current_positions).and_return([])
    allow(alpaca_double).to receive(:cancel_all_orders).and_return(0)
    
    # Mock market data for sizing
    sample_bar = { close: BigDecimal('150.00'), high: BigDecimal('155.00'), low: BigDecimal('145.00'), timestamp: Time.current }
    allow(alpaca_double).to receive(:get_bars).and_return([sample_bar] * 20)
    allow(alpaca_double).to receive(:get_bars_multi).and_return({ symbol => [sample_bar] * 20 })

    allow(alpaca_double).to receive(:place_order).and_return({
      'id' => 'order-123',
      'status' => 'filled',
      'qty' => '100',
      'filled_qty' => '100',
      'filled_avg_price' => '150.00'
    })
    
    # 3. Setup strategy config
    config_path = Rails.root.join('config/portfolio_strategies.yml')
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(config_path).and_return(true)
    allow(YAML).to receive(:load_file).with(config_path).and_return({
      'paper' => {
        'strategies' => {
          'insider' => { 'enabled' => false, 'weight' => 0.0 },
          'congressional' => { 'enabled' => true, 'weight' => 1.0 }
        }
      }
    })
  end

  it 'completes the full loop from ingestion to execution with comprehensive audit trail' do
    # 1. Run Daily Trading Workflow
    # We skip politician scoring because it's complex to setup in integration test
    result = Workflows::ExecuteDailyTrading.call(
      trading_mode: 'paper',
      skip_politician_scoring: true
    )

    puts "QuiverTrade count: #{QuiverTrade.count}"
    puts "Workflow failure: #{result.full_error_message}" unless result.success?
    puts "Target positions: #{result.target_positions.map(&:symbol) if result.target_positions}"
    puts "Orders placed: #{result.orders_placed.inspect}" if result.orders_placed
    expect(result.success?).to be true

    # 2. Verify Data Ingestion Audit
    run = AuditTrail::DataIngestionRun.last
    puts "Ingestion run error: #{run.error_message}" if run.status == 'failed'
    expect(run.task_name).to eq('Workflows::FetchTradingData') # Called within the workflow
    expect(run.status).to eq('completed')
    expect(run.quiver_trades.count).to be >= 1
    expect(run.api_call_logs.count).to be >= 1

    # 3. Verify Trade Decisions (Outbox)
    decision = AuditTrail::TradeDecision.last
    expect(decision.symbol).to eq(symbol)
    expect(decision.status).to eq('executed')
    expect(decision.primary_quiver_trade).to be_present
    expect(decision.primary_ingestion_run).to eq(run)
    expect(decision.decision_rationale['data_lineage']).to be_present

    # 4. Verify Trade Executions
    execution = AuditTrail::TradeExecution.last
    expect(execution.trade_decision).to eq(decision)
    expect(execution.status).to eq('filled')
    expect(execution.alpaca_order_id).to eq('order-123')
    expect(execution.api_request_payload).to be_present
    expect(execution.api_response_payload).to be_present
  end
end
