# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditTrail::LogDataIngestion, type: :command do
  describe '.call' do
    let(:task_name) { 'data_fetch:congress_daily' }
    let(:data_source) { 'quiverquant_congress' }

    context 'with successful execution' do
      it 'creates a DataIngestionRun record' do
        expect do
          described_class.call(task_name: task_name, data_source: data_source) do
            { fetched: 10, created: 5, updated: 3, skipped: 2 }
          end
        end.to change(AuditTrail::DataIngestionRun, :count).by(1)
      end

      it 'sets run status to completed' do
        result = described_class.call(task_name: task_name, data_source: data_source) do
          { fetched: 10, created: 5, updated: 3, skipped: 2 }
        end

        expect(result.run.status).to eq('completed')
        expect(result.run.completed_at).to be_present
      end

      it 'records correct counts' do
        result = described_class.call(task_name: task_name, data_source: data_source) do
          { fetched: 10, created: 5, updated: 3, skipped: 2 }
        end

        run = result.run
        expect(run.records_fetched).to eq(10)
        expect(run.records_created).to eq(5)
        expect(run.records_updated).to eq(3)
        expect(run.records_skipped).to eq(2)
      end

      it 'records date range when provided' do
        start_date = Date.new(2025, 1, 1)
        end_date = Date.new(2025, 1, 31)

        result = described_class.call(task_name: task_name, data_source: data_source) do
          {
            fetched: 10,
            created: 5,
            updated: 3,
            skipped: 2,
            date_range: [start_date, end_date]
          }
        end

        run = result.run
        expect(run.data_date_start).to eq(start_date)
        expect(run.data_date_end).to eq(end_date)
      end

      it 'returns a successful context' do
        result = described_class.call(task_name: task_name, data_source: data_source) do
          { fetched: 10, created: 5, updated: 3, skipped: 2 }
        end

        expect(result.success?).to be true
      end
    end

    context 'with execution failure' do
      it 'sets run status to failed' do
        # GLCommand catches the error unless raise_errors: true is passed
        result = described_class.call(task_name: task_name, data_source: data_source) do
          raise StandardError, 'API connection failed'
        end

        expect(result.success?).to be false

        run = AuditTrail::DataIngestionRun.last
        expect(run.status).to eq('failed')
        expect(run.failed_at).to be_present
        expect(run.error_message).to eq('API connection failed')
      end

      it 'records error details' do
        described_class.call(task_name: task_name, data_source: data_source) do
          raise StandardError, 'API connection failed'
        end

        run = AuditTrail::DataIngestionRun.last
        expect(run.error_details).to include('class' => 'StandardError')
        expect(run.error_details['backtrace']).to be_an(Array)
      end

      it 're-raises when raise_errors: true is passed' do
        expect do
          described_class.call(task_name: task_name, data_source: data_source, raise_errors: true) do
            raise StandardError, 'API connection failed'
          end
        end.to raise_error(StandardError, 'API connection failed')
      end
    end

    context 'with record operations' do
      let!(:trade1) { create(:quiver_trade) }
      let!(:trade2) { create(:quiver_trade) }

      it 'creates junction records for tracked records' do
        expect do
          described_class.call(task_name: task_name, data_source: data_source) do
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
        result = described_class.call(task_name: task_name, data_source: data_source) do
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

        run = result.run
        expect(run.data_ingestion_run_records.count).to eq(2)
        expect(run.quiver_trades).to include(trade1, trade2)
      end
    end

    context 'with API call logs' do
      it 'creates ApiPayload records for API calls' do
        expect do
          described_class.call(task_name: task_name, data_source: data_source) do
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

      it 'creates ApiCallLog linking request and response' do
        expect do
          described_class.call(task_name: task_name, data_source: data_source) do
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

      it 'stores API calls with normalized source' do
        described_class.call(task_name: task_name, data_source: data_source) do
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

        expect(request.source).to eq('quiverquant')
        expect(response.source).to eq('quiverquant')
      end
    end
  end
end
