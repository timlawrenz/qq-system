# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Performance Analysis Integration Flow', type: :request do
  describe 'complete performance analysis workflow' do
    let(:algorithm) { create(:algorithm) }
    let(:start_date) { Date.parse('2024-01-01') }
    let(:end_date) { Date.parse('2024-01-05') }

    # Expected performance metrics that should be returned
    let(:expected_performance_metrics) do
      {
        'total_pnl' => 5000.0,
        'total_pnl_percentage' => 5.0,
        'annualized_return' => 60.0,
        'volatility' => 0.15,
        'sharpe_ratio' => 1.25,
        'max_drawdown' => 2.3,
        'calmar_ratio' => 2.5,
        'win_loss_ratio' => 1.5,
        'portfolio_time_series' => {
          '2024-01-01' => 100_000.0,
          '2024-01-05' => 105_000.0
        },
        'calculated_at' => Time.current.iso8601
      }
    end

    let(:mock_alpaca_client) { instance_double(AlpacaApiClient) }
    let(:sample_bars_data) do
      [
        {
          symbol: 'AAPL',
          timestamp: Time.zone.parse('2024-01-01 09:30:00 UTC'),
          open: BigDecimal('150.0'),
          high: BigDecimal('155.0'),
          low: BigDecimal('149.0'),
          close: BigDecimal('152.0'),
          volume: 1000
        },
        {
          symbol: 'AAPL',
          timestamp: Time.zone.parse('2024-01-02 09:30:00 UTC'),
          open: BigDecimal('152.0'),
          high: BigDecimal('157.0'),
          low: BigDecimal('151.0'),
          close: BigDecimal('154.0'),
          volume: 1200
        }
      ]
    end

    before do
      # Mock external Alpaca API calls
      allow(AlpacaApiClient).to receive(:new).and_return(mock_alpaca_client)
      allow(mock_alpaca_client).to receive(:fetch_bars).and_return(sample_bars_data)

      # Create trades for the algorithm
      create(:trade,
             algorithm: algorithm,
             symbol: 'AAPL',
             side: 'buy',
             quantity: 100.0,
             price: 150.0,
             executed_at: Time.zone.parse('2024-01-01 10:00:00 UTC'))

      create(:trade,
             algorithm: algorithm,
             symbol: 'AAPL',
             side: 'sell',
             quantity: 100.0,
             price: 157.5,
             executed_at: Time.zone.parse('2024-01-02 11:00:00 UTC'))

      create(:trade,
             algorithm: algorithm,
             symbol: 'AAPL',
             side: 'buy',
             quantity: 200.0,
             price: 154.0,
             executed_at: Time.zone.parse('2024-01-03 14:00:00 UTC'))
    end

    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    it 'completes the entire performance analysis workflow' do
      # Step 1: Make POST request to start analysis
      analysis_params = {
        algorithm_id: algorithm.id,
        start_date: start_date.to_s,
        end_date: end_date.to_s
      }

      expect do
        post '/api/v1/analyses', params: analysis_params
      end.to change(Analysis, :count).by(1)

      expect(response).to have_http_status(:created)

      # Step 2: Verify response shows pending status
      json_response = response.parsed_body
      expect(json_response).to include(
        'analysis_id' => kind_of(Integer),
        'status' => 'pending'
      )
      expect(json_response).not_to have_key('results')

      analysis_id = json_response['analysis_id']

      # Step 3: Execute background job inline (instead of async)
      # Mock the AnalysePerformance command to return expected results
      mock_command_result = AnalysePerformance.build_context(results: expected_performance_metrics)
      allow(AnalysePerformance).to receive(:call!).and_return(mock_command_result)

      AnalysePerformanceJob.perform_now(analysis_id)

      # Step 4: Make GET request to fetch analysis results
      get "/api/v1/analyses/#{analysis_id}"

      expect(response).to have_http_status(:ok)

      # Step 5: Verify status is now completed
      result_response = response.parsed_body
      expect(result_response).to include(
        'analysis_id' => analysis_id,
        'status' => 'completed'
      )

      # Step 6: Assert results contain expected performance metrics
      expect(result_response).to have_key('results')
      results = result_response['results']

      # Verify all expected performance metrics are present
      expect(results).to include(
        'total_pnl' => 5000.0,
        'total_pnl_percentage' => 5.0,
        'sharpe_ratio' => 1.25,
        'max_drawdown' => 2.3
      )

      # Verify portfolio time series is included
      expect(results).to have_key('portfolio_time_series')
      expect(results['portfolio_time_series']).to be_a(Hash)
      expect(results['portfolio_time_series']).to include(
        '2024-01-01' => 100_000.0,
        '2024-01-05' => 105_000.0
      )

      # Verify calculation timestamp
      expect(results).to have_key('calculated_at')
      expect(results['calculated_at']).to be_present

      # Verify additional performance metrics with plausible values
      expect(results['annualized_return']).to be_a(Numeric)
      expect(results['volatility']).to be_a(Numeric)
      expect(results['calmar_ratio']).to be_a(Numeric)
      expect(results['win_loss_ratio']).to be_a(Numeric)
    end
    # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

    context 'when analysis fails' do
      before do
        # Create trades for the algorithm
        create(:trade,
               algorithm: algorithm,
               symbol: 'AAPL',
               side: 'buy',
               quantity: 100.0,
               price: 150.0,
               executed_at: Time.zone.parse('2024-01-01 10:00:00 UTC'))
      end

      it 'handles failure gracefully' do
        # Step 1: Start analysis
        analysis_params = {
          algorithm_id: algorithm.id,
          start_date: start_date.to_s,
          end_date: end_date.to_s
        }

        post '/api/v1/analyses', params: analysis_params
        expect(response).to have_http_status(:created)

        analysis_id = response.parsed_body['analysis_id']

        # Step 2: Mock command failure
        mock_command_result = double(success?: false, error: 'No trades found') # rubocop:disable RSpec/VerifiedDoubles
        allow(AnalysePerformance).to receive(:call!).and_return(mock_command_result)

        # Step 3: Execute job with failure
        AnalysePerformanceJob.perform_now(analysis_id)

        # Step 4: Verify analysis is marked as failed
        get "/api/v1/analyses/#{analysis_id}"
        expect(response).to have_http_status(:ok)

        result_response = response.parsed_body
        expect(result_response).to include(
          'analysis_id' => analysis_id,
          'status' => 'failed'
        )
        expect(result_response).not_to have_key('results')
      end
    end
  end
end
