# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Analyses', type: :request do
  let(:algorithm) { create(:algorithm) }

  describe 'POST /api/v1/analyses' do
    let(:valid_params) do
      {
        algorithm_id: algorithm.id,
        start_date: '2024-01-01',
        end_date: '2024-01-05'
      }
    end

    context 'with valid parameters' do
      it 'creates a new analysis and returns it' do
        expect do
          post '/api/v1/analyses', params: valid_params
        end.to change(Analysis, :count).by(1)

        expect(response).to have_http_status(:created)

        json_response = JSON.parse(response.body)
        expect(json_response).to include(
          'analysis_id' => kind_of(Integer),
          'status' => 'pending'
        )
        expect(json_response).not_to have_key('results')
      end

      it 'calls InitiatePerformanceAnalysis command with correct parameters' do
        expect(InitiatePerformanceAnalysis).to receive(:call).with(
          algorithm_id: algorithm.id,
          start_date: Date.parse('2024-01-01'),
          end_date: Date.parse('2024-01-05')
        ).and_call_original

        post '/api/v1/analyses', params: valid_params
      end

      it 'enqueues a background job for analysis' do
        expect(AnalysePerformanceJob).to receive(:perform_later).with(kind_of(Integer))

        post '/api/v1/analyses', params: valid_params
      end
    end

    context 'with minimal parameters' do
      it 'creates analysis with algorithm_id only' do
        minimal_params = { algorithm_id: algorithm.id }

        expect do
          post '/api/v1/analyses', params: minimal_params
        end.to change(Analysis, :count).by(1)

        expect(response).to have_http_status(:created)

        json_response = JSON.parse(response.body)
        expect(json_response).to include(
          'analysis_id' => kind_of(Integer),
          'status' => 'pending'
        )
      end
    end

    context 'with invalid parameters' do
      it 'returns validation errors when algorithm is not found' do
        invalid_params = valid_params.merge(algorithm_id: 99_999)

        post '/api/v1/analyses', params: invalid_params

        expect(response).to have_http_status(:unprocessable_entity)

        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_present
      end

      it 'returns validation errors when algorithm_id is missing' do
        invalid_params = valid_params.except(:algorithm_id)

        post '/api/v1/analyses', params: invalid_params

        expect(response).to have_http_status(:unprocessable_entity)

        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_present
      end
    end

    context 'with invalid date format' do
      it 'handles invalid date gracefully' do
        invalid_params = valid_params.merge(start_date: 'invalid-date', end_date: '2030-01-05')

        post '/api/v1/analyses', params: invalid_params

        # Should still work as invalid dates are parsed as nil and replaced with defaults
        expect(response).to have_http_status(:created)
      end
    end
  end

  describe 'GET /api/v1/analyses/:id' do
    context 'when analysis exists and is pending' do
      let(:analysis) { create(:analysis, algorithm: algorithm, status: 'pending') }

      it 'returns the analysis without results' do
        get "/api/v1/analyses/#{analysis.id}"

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response).to include(
          'analysis_id' => analysis.id,
          'status' => 'pending'
        )
        expect(json_response).not_to have_key('results')
      end
    end

    context 'when analysis exists and is completed' do
      let(:results) { { 'total_pnl' => 1000.0, 'sharpe_ratio' => 1.5 } }
      let(:analysis) { create(:analysis, algorithm: algorithm, status: 'completed', results: results) }

      it 'returns the analysis with results' do
        get "/api/v1/analyses/#{analysis.id}"

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response).to include(
          'analysis_id' => analysis.id,
          'status' => 'completed',
          'results' => results
        )
      end
    end

    context 'when analysis exists and is running' do
      let(:analysis) { create(:analysis, algorithm: algorithm, status: 'running') }

      it 'returns the analysis without results' do
        get "/api/v1/analyses/#{analysis.id}"

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response).to include(
          'analysis_id' => analysis.id,
          'status' => 'running'
        )
        expect(json_response).not_to have_key('results')
      end
    end

    context 'when analysis exists and has failed' do
      let(:analysis) { create(:analysis, algorithm: algorithm, status: 'failed') }

      it 'returns the analysis without results' do
        get "/api/v1/analyses/#{analysis.id}"

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response).to include(
          'analysis_id' => analysis.id,
          'status' => 'failed'
        )
        expect(json_response).not_to have_key('results')
      end
    end

    context 'when analysis does not exist' do
      it 'returns 404' do
        get '/api/v1/analyses/99999'

        expect(response).to have_http_status(:not_found)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Analysis not found')
      end
    end
  end
end
