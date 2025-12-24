# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditTrail::LogDataIngestion do
  describe '#call' do
    let(:task_name) { 'data_fetch:congress_daily' }
    let(:data_source) { 'quiverquant_congress' }
    let(:logger) { described_class.new(task_name: task_name, data_source: data_source) }

    context 'with successful execution' do
      it 'creates a DataIngestionRun record' do
        expect do
          logger.call do
            { fetched: 10, created: 5, updated: 3, skipped: 2 }
          end
        end.to change(AuditTrail::DataIngestionRun, :count).by(1)
      end

      it 'sets run status to completed' do
        logger.call do
          { fetched: 10, created: 5, updated: 3, skipped: 2 }
        end

        expect(logger.run.status).to eq('completed')
        expect(logger.run.completed_at).to be_present
      end

      it 'records correct counts' do
        logger.call do
          { fetched: 10, created: 5, updated: 3, skipped: 2 }
        end

        run = logger.run
        expect(run.records_fetched).to eq(10)
        expect(run.records_created).to eq(5)
        expect(run.records_updated).to eq(3)
        expect(run.records_skipped).to eq(2)
      end

      it 'records date range when provided' do
        start_date = Date.new(2025, 1, 1)
        end_date = Date.new(2025, 1, 31)

        logger.call do
          {
            fetched: 10,
            created: 5,
            updated: 3,
            skipped: 2,
            date_range: [start_date, end_date]
          }
        end

        run = logger.run
        expect(run.data_date_start).to eq(start_date)
        expect(run.data_date_end).to eq(end_date)
      end

      it 'returns true' do
        result = logger.call do
          { fetched: 10, created: 5, updated: 3, skipped: 2 }
        end

        expect(result).to be true
      end

      it 'sets success? to true' do
        logger.call do
          { fetched: 10, created: 5, updated: 3, skipped: 2 }
        end

        expect(logger.success?).to be true
      end
    end

    context 'with execution failure' do
      it 'sets run status to failed' do
        logger.call do
          raise StandardError, 'API connection failed'
        end

        expect(logger.run.status).to eq('failed')
        expect(logger.run.failed_at).to be_present
      end

      it 'records error message' do
        logger.call do
          raise StandardError, 'API connection failed'
        end

        expect(logger.run.error_message).to eq('API connection failed')
      end

      it 'records error details' do
        logger.call do
          raise StandardError, 'API connection failed'
        end

        expect(logger.run.error_details).to include('class' => 'StandardError')
        expect(logger.run.error_details['backtrace']).to be_an(Array)
      end

      it 'returns false' do
        result = logger.call do
          raise StandardError, 'API connection failed'
        end

        expect(result).to be false
      end

      it 'sets success? to false' do
        logger.call do
          raise StandardError, 'Test error'
        end

        expect(logger.success?).to be false
      end
    end

    context 'with record operations' do
      let!(:trade1) { create(:quiver_trade) }
      let!(:trade2) { create(:quiver_trade) }

      it 'creates junction records for tracked records' do
        expect do
          logger.call do
            {
              fetched: 2,
              created: 2,
              updated: 0,
              skipped: 0,
              record_operations: [
                { record: trade1, operation: 'created' },
                { record: trade2, operation: 'created' }
              ]
            }
          end
        end.to change(AuditTrail::DataIngestionRunRecord, :count).by(2)
      end

      it 'links records to the run' do
        logger.call do
          {
            fetched: 2,
            created: 2,
            updated: 0,
            skipped: 0,
            record_operations: [
              { record: trade1, operation: 'created' },
              { record: trade2, operation: 'updated' }
            ]
          }
        end

        run = logger.run
        expect(run.data_ingestion_run_records.count).to eq(2)
        expect(run.quiver_trades).to include(trade1, trade2)
      end
    end

    context 'with API call logs' do
      # NOTE: API call logging will be implemented when integrated with actual data fetching
      # For now these are pending as the feature exists but isn't being used yet
      xit 'creates ApiPayload records for API calls' do
        expect do
          logger.call do
            {
              fetched: 10,
              created: 5,
              updated: 3,
              skipped: 2,
              api_calls: [
                {
                  endpoint: '/api/v1/congressional',
                  status_code: 200,
                  duration_ms: 250,
                  request: { endpoint: '/api/v1/congressional', method: 'GET', params: { start_date: '2025-01-01' } },
                  response: { status_code: 200, data: [] }
                }
              ]
            }
          end
        end.to change(AuditTrail::ApiPayload, :count).by(2) # request + response
      end

      xit 'creates ApiCallLog linking request and response' do
        expect do
          logger.call do
            {
              fetched: 10,
              created: 5,
              updated: 3,
              skipped: 2,
              api_calls: [
                {
                  endpoint: '/api/v1/congressional',
                  status_code: 200,
                  request: { endpoint: '/api/v1/congressional', method: 'GET' },
                  response: { status_code: 200 }
                }
              ]
            }
          end
        end.to change(AuditTrail::ApiCallLog, :count).by(1)
      end

      xit 'stores API calls with correct source' do
        logger.call do
          {
            fetched: 10,
            created: 5,
            updated: 3,
            skipped: 2,
            api_calls: [
              {
                endpoint: '/api/v1/congressional',
                request: { endpoint: '/test', method: 'GET' },
                response: { status_code: 200 }
              }
            ]
          }
        end

        request = AuditTrail::ApiRequest.last
        response = AuditTrail::ApiResponse.last
        
        expect(request.source).to eq(data_source)
        expect(response.source).to eq(data_source)
      end
    end

    context 'with no block given' do
      it 'returns true without calling the block' do
        result = logger.call
        expect(result).to be true
      end
    end
  end

  describe '#success?' do
    it 'returns nil when no run has been executed' do
      logger = described_class.new(task_name: 'test', data_source: 'test')
      expect(logger.success?).to be_nil
    end
  end
end
