# frozen_string_literal: true

# API::V1::TradesController
#
# Controller for managing trades via API endpoints.
# Delegates all business logic to GLCommand objects.
module Api
  module V1
    class TradesController < ApplicationController
      before_action :find_algorithm, only: [:create]
      before_action :find_trade, only: %i[show update destroy]

      # GET /api/v1/trades/:id
      def show
        render json: { trade: trade_json(@trade) }
      end

      # POST /api/v1/algorithms/:algorithm_id/trades
      def create
        result = CreateTrade.call(
          algorithm: @algorithm,
          symbol: trade_params[:symbol],
          executed_at: trade_params[:executed_at],
          side: trade_params[:side],
          quantity: trade_params[:quantity],
          price: trade_params[:price]
        )

        if result.success?
          render json: { trade: trade_json(result.trade) }, status: :created
        else
          render json: { errors: result.errors }, status: :unprocessable_entity
        end
      end

      # PUT/PATCH /api/v1/trades/:id
      def update
        result = UpdateTrade.call(
          trade: @trade,
          symbol: trade_params[:symbol],
          executed_at: trade_params[:executed_at],
          side: trade_params[:side],
          quantity: trade_params[:quantity],
          price: trade_params[:price]
        )

        if result.success?
          render json: { trade: trade_json(result.trade) }
        else
          render json: { errors: result.errors }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/trades/:id
      def destroy
        result = DeleteTrade.call(trade: @trade)

        if result.success?
          head :no_content
        else
          render json: { errors: result.errors }, status: :unprocessable_entity
        end
      end

      private

      def find_algorithm
        @algorithm = Algorithm.find(params[:algorithm_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Algorithm not found' }, status: :not_found
      end

      def find_trade
        @trade = Trade.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Trade not found' }, status: :not_found
      end

      def trade_params
        params.require(:trade).permit(:symbol, :executed_at, :side, :quantity, :price)
      end

      def trade_json(trade)
        {
          id: trade.id,
          algorithm_id: trade.algorithm_id,
          symbol: trade.symbol,
          executed_at: trade.executed_at,
          side: trade.side,
          quantity: trade.quantity.to_f,
          price: trade.price.to_f,
          created_at: trade.created_at,
          updated_at: trade.updated_at
        }
      end
    end
  end
end
