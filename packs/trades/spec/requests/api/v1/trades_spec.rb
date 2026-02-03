# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Trades', type: :request do
  let(:algorithm) { create(:algorithm) }
  let(:trade) { create(:trade, algorithm: algorithm) }

  describe 'POST /api/v1/algorithms/:algorithm_id/trades' do
    let(:valid_params) do
      {
        trade: {
          symbol: 'AAPL',
          executed_at: '2024-01-15T10:30:00Z',
          side: 'buy',
          quantity: 100,
          price: 150.50
        }
      }
    end

    context 'with valid parameters' do
      it 'creates a new trade and returns it' do
        expect do
          post "/api/v1/algorithms/#{algorithm.id}/trades", params: valid_params
        end.to change(Trade, :count).by(1)

        expect(response).to have_http_status(:created)

        json_response = JSON.parse(response.body)
        expect(json_response['trade']).to include(
          'symbol' => 'AAPL',
          'side' => 'buy',
          'quantity' => 100.0,
          'price' => 150.50,
          'algorithm_id' => algorithm.id
        )
      end

      it 'calls CreateTrade command with correct parameters' do
        expect(CreateTrade).to receive(:call).with(
          algorithm: algorithm,
          symbol: 'AAPL',
          executed_at: '2024-01-15T10:30:00Z',
          side: 'buy',
          quantity: '100',
          price: '150.5'
        ).and_call_original

        post "/api/v1/algorithms/#{algorithm.id}/trades", params: valid_params
      end
    end

    context 'with invalid parameters' do
      it 'returns validation errors when trade data is invalid' do
        invalid_params = valid_params.deep_merge(trade: { symbol: '' })

        post "/api/v1/algorithms/#{algorithm.id}/trades", params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)

        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_present
      end

      it 'returns 404 when algorithm is not found' do
        post '/api/v1/algorithms/99999/trades', params: valid_params

        expect(response).to have_http_status(:not_found)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Algorithm not found')
      end
    end
  end

  describe 'GET /api/v1/trades/:id' do
    context 'when trade exists' do
      it 'returns the trade' do
        get "/api/v1/trades/#{trade.id}"

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['trade']).to include(
          'id' => trade.id,
          'symbol' => trade.symbol,
          'side' => trade.side,
          'quantity' => trade.quantity.to_f,
          'price' => trade.price.to_f,
          'algorithm_id' => trade.algorithm_id
        )
      end
    end

    context 'when trade does not exist' do
      it 'returns 404' do
        get '/api/v1/trades/99999'

        expect(response).to have_http_status(:not_found)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Trade not found')
      end
    end
  end

  describe 'PUT /api/v1/trades/:id' do
    let(:update_params) do
      {
        trade: {
          symbol: 'MSFT',
          quantity: 200,
          price: 175.25
        }
      }
    end

    context 'with valid parameters' do
      it 'updates the trade and returns it' do
        put "/api/v1/trades/#{trade.id}", params: update_params

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['trade']).to include(
          'id' => trade.id,
          'symbol' => 'MSFT',
          'quantity' => 200.0,
          'price' => 175.25
        )

        trade.reload
        expect(trade.symbol).to eq('MSFT')
        expect(trade.quantity).to eq(200.0)
        expect(trade.price).to eq(175.25)
      end

      it 'calls UpdateTrade command with correct parameters' do
        expect(UpdateTrade).to receive(:call).with(
          trade: trade,
          symbol: 'MSFT',
          executed_at: nil,
          side: nil,
          quantity: '200',
          price: '175.25'
        ).and_call_original

        put "/api/v1/trades/#{trade.id}", params: update_params
      end
    end

    context 'with invalid parameters' do
      it 'returns validation errors when trade data is invalid' do
        invalid_params = { trade: { quantity: -10 } }

        put "/api/v1/trades/#{trade.id}", params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)

        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_present
      end
    end

    context 'when trade does not exist' do
      it 'returns 404' do
        put '/api/v1/trades/99999', params: update_params

        expect(response).to have_http_status(:not_found)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Trade not found')
      end
    end
  end

  describe 'PATCH /api/v1/trades/:id' do
    let(:update_params) do
      {
        trade: {
          symbol: 'GOOGL'
        }
      }
    end

    context 'with valid parameters' do
      it 'updates the trade and returns it' do
        patch "/api/v1/trades/#{trade.id}", params: update_params

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['trade']).to include(
          'id' => trade.id,
          'symbol' => 'GOOGL'
        )

        trade.reload
        expect(trade.symbol).to eq('GOOGL')
      end
    end
  end

  describe 'DELETE /api/v1/trades/:id' do
    context 'when trade exists' do
      it 'deletes the trade and returns 204 No Content' do
        trade_id = trade.id

        expect do
          delete "/api/v1/trades/#{trade_id}"
        end.to change(Trade, :count).by(-1)

        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty
      end

      it 'calls DeleteTrade command with correct parameters' do
        expect(DeleteTrade).to receive(:call).with(
          trade: trade
        ).and_call_original

        delete "/api/v1/trades/#{trade.id}"
      end
    end

    context 'when trade does not exist' do
      it 'returns 404' do
        delete '/api/v1/trades/99999'

        expect(response).to have_http_status(:not_found)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Trade not found')
      end
    end
  end
end
