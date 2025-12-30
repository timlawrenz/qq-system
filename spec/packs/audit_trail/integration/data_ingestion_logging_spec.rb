# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Data Ingestion Logging Integration' do
  let(:task_name) { 'data_fetch:congress_daily' }
  let(:data_source) { 'quiverquant_congress' }

  it 'logs a complete congress data fetch with records and API calls' do
    # 1. Simulate a rake task execution using the command
    command = AuditTrail::LogDataIngestion.call(
      task_name: task_name,
      data_source: data_source
    ) do |_run|
      # 2. Simulate fetching and persisting records
      # In a real scenario, this would be FetchQuiverData.call
      qt1 = create(:quiver_trade, ticker: 'AAPL')
      qt2 = create(:quiver_trade, ticker: 'MSFT')

      # 3. Return the result hash in the format expected by LogDataIngestion
      {
        fetched: 2,
        created: 2,
        updated: 0,
        skipped: 0,
        date_range: [7.days.ago.to_date, Date.current],
        record_operations: [
          { record: qt1, operation: 'created' },
          { record: qt2, operation: 'created' }
        ],
        api_calls: [
          {
            endpoint: '/api/v1/congressional',
            status_code: 200,
            duration_ms: 150,
            request: { method: 'GET', endpoint: '/api/v1/congressional', params: { days: 7 } },
            response: { status_code: 200, body: '[]' }
          }
        ]
      }
    end

    # 4. Verify the audit trail
    expect(command.success?).to be true
    run = command.run

    # Check DataIngestionRun
    expect(run.status).to eq('completed')
    expect(run.records_created).to eq(2)
    expect(run.data_source).to eq(data_source)

    # Check junction records (DataIngestionRunRecord)
    expect(run.data_ingestion_run_records.count).to eq(2)
    expect(run.quiver_trades.count).to eq(2)
    expect(run.quiver_trades.map(&:ticker)).to contain_exactly('AAPL', 'MSFT')

    # Check API logs
    expect(run.api_call_logs.count).to eq(1)
    log = run.api_call_logs.first
    expect(log.endpoint).to eq('/api/v1/congressional')
    expect(log.http_status_code).to eq(200)

    # Check payloads
    expect(log.api_request_payload).to be_present
    expect(log.api_request_payload.source).to eq('quiverquant')
    expect(log.api_response_payload).to be_present
    expect(log.api_response_payload.status_code).to eq(200)
  end

  it 'records failure and error details when an error occurs' do
    expect do
      AuditTrail::LogDataIngestion.call(
        task_name: task_name,
        data_source: data_source,
        raise_errors: true # So we can catch it here
      ) do
        raise StandardError, 'Connection timed out'
      end
    end.to raise_error(StandardError, 'Connection timed out')

    run = AuditTrail::DataIngestionRun.last
    expect(run.status).to eq('failed')
    expect(run.error_message).to eq('Connection timed out')
    expect(run.failed_at).to be_present
    expect(run.error_details['class']).to eq('StandardError')
  end
end
