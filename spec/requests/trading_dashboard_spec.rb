# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trading Dashboard', type: :request do
  before do
    Rails.cache.clear
  end

  it 'renders an empty state when no DB snapshot exists' do
    expect(AlpacaService).not_to receive(:new)

    get '/dashboard'

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/html')
    expect(response.body).to include('No performance snapshots found')
  end

  # rubocop:disable RSpec/ExampleLength
  it 'renders metrics from the local database without calling Alpaca' do
    create(
      :performance_snapshot,
      snapshot_date: Date.current,
      total_equity: 123_456.78,
      metadata: {
        'snapshot_captured_at' => Time.current.iso8601,
        'account' => {
          'cash' => 23_000.0,
          'invested' => 100_456.78,
          'cash_pct' => 18.63,
          'invested_pct' => 81.37,
          'position_count' => 2
        },
        'positions' => [
          { 'symbol' => 'AAPL', 'side' => 'long', 'qty' => 10, 'market_value' => 60_000.0 },
          { 'symbol' => 'MSFT', 'side' => 'long', 'qty' => 5, 'market_value' => 40_456.78 }
        ],
        'top_positions' => [
          { 'symbol' => 'AAPL', 'side' => 'long', 'qty' => 10, 'market_value' => 60_000.0 }
        ],
        'risk' => {
          'concentration_pct' => 48.6,
          'concentration_symbol' => 'AAPL'
        },
        'period' => {
          'start_date' => 30.days.ago.to_date.to_s,
          'end_date' => Date.current.to_s,
          'trading_days' => 30
        }
      }
    )

    expect(AlpacaService).not_to receive(:new)

    get '/dashboard'

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/html')
    expect(response.body).to include('Trading Dashboard')
    expect(response.body).to include('Scope:')
    expect(response.body).to include('123456.78')
    expect(response.body).to include('AAPL')
  end
  # rubocop:enable RSpec/ExampleLength
end
