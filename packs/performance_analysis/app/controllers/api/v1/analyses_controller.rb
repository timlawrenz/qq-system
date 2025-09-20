# frozen_string_literal: true

# API::V1::AnalysesController
#
# Controller for managing analyses via API endpoints.
# Delegates all business logic to GLCommand objects.
module Api
  module V1
    class AnalysesController < ApplicationController
      before_action :find_analysis, only: [:show]

      # GET /api/v1/analyses/:id
      def show
        render json: analysis_json(@analysis)
      end

      # POST /api/v1/analyses
      def create
        algorithm_id = analysis_params[:algorithm_id]&.to_i
        if algorithm_id.blank? || algorithm_id.zero?
          return render json: { errors: ['Algorithm ID is required'] },
                        status: :unprocessable_entity
        end

        # Determine date range with defaults
        start_date, end_date = determine_date_range(algorithm_id)

        result = InitiatePerformanceAnalysis.call(
          algorithm_id: algorithm_id,
          start_date: start_date,
          end_date: end_date
        )

        if result.success?
          render json: analysis_json(result.analysis), status: :created
        else
          render json: { errors: format_errors(result.errors) }, status: :unprocessable_entity
        end
      end

      private

      def find_analysis
        @analysis = Analysis.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Analysis not found' }, status: :not_found
      end

      def analysis_params
        params.permit(:algorithm_id, :start_date, :end_date)
      end

      def parse_date(date_string)
        return nil if date_string.blank?

        Date.parse(date_string)
      rescue Date::Error
        nil
      end

      def determine_date_range(algorithm_id)
        start_date = parse_date(analysis_params[:start_date])
        end_date = parse_date(analysis_params[:end_date])

        # If no dates provided, use the algorithm's trade date range
        if start_date.nil? || end_date.nil?
          trades = Trade.where(algorithm_id: algorithm_id)

          if trades.exists?
            start_date ||= trades.minimum(:executed_at)&.to_date
            end_date ||= trades.maximum(:executed_at)&.to_date
          end

          # Fallback to reasonable defaults if no trades exist
          start_date ||= 1.month.ago.to_date
          end_date ||= Date.current
        end

        [start_date, end_date]
      end

      def format_errors(errors)
        if errors.respond_to?(:full_messages)
          errors.full_messages
        elsif errors.is_a?(Hash)
          errors.map { |field, messages| "#{field.to_s.humanize} #{Array(messages).join(', ')}" }
        else
          [errors.to_s]
        end
      end

      def analysis_json(analysis)
        response = {
          analysis_id: analysis.id,
          status: analysis.status
        }

        # Include results if analysis is completed
        response[:results] = analysis.results if analysis.status == 'completed'

        response
      end
    end
  end
end
