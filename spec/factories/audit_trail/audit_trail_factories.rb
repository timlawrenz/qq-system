# frozen_string_literal: true

FactoryBot.define do
  factory :data_ingestion_run, class: 'AuditTrail::DataIngestionRun' do
    run_id { SecureRandom.uuid }
    task_name { 'data_fetch:congress_daily' }
    data_source { 'quiverquant_congress' }
    started_at { Time.current }
    status { 'running' }
    records_fetched { 0 }
    records_created { 0 }
    records_updated { 0 }
    records_skipped { 0 }

    trait :completed do
      status { 'completed' }
      completed_at { started_at + 45.seconds }
      records_fetched { 100 }
      records_created { 80 }
      records_updated { 15 }
      records_skipped { 5 }
    end

    trait :failed do
      status { 'failed' }
      failed_at { started_at + 10.seconds }
      error_message { 'API connection failed' }
      error_details { { class: 'Faraday::ConnectionFailed', backtrace: ['line 1', 'line 2'] } }
    end

    trait :insider_source do
      task_name { 'data_fetch:insider_daily' }
      data_source { 'quiverquant_insider' }
    end
  end

  factory :data_ingestion_run_record, class: 'AuditTrail::DataIngestionRunRecord' do
    association :data_ingestion_run
    association :record, factory: :quiver_trade
    operation { 'created' }

    trait :updated do
      operation { 'updated' }
    end

    trait :skipped do
      operation { 'skipped' }
    end
  end

  factory :api_payload, class: 'AuditTrail::ApiPayload' do
    source { 'quiverquant' }
    captured_at { Time.current }
    payload { { endpoint: '/api/v1/test', data: 'test' } }

    factory :api_request, class: 'AuditTrail::ApiRequest' do
      type { 'AuditTrail::ApiRequest' }
      payload do
        {
          endpoint: '/api/v1/congressional',
          method: 'GET',
          params: { start_date: '2025-01-01', end_date: '2025-01-31' }
        }
      end

      trait :alpaca do
        source { 'alpaca' }
        payload do
          {
            endpoint: '/v2/orders',
            method: 'POST',
            payload: { symbol: 'AAPL', qty: 10, side: 'buy' }
          }
        end
      end
    end

    factory :api_response, class: 'AuditTrail::ApiResponse' do
      type { 'AuditTrail::ApiResponse' }
      payload do
        {
          status_code: 200,
          data: [{ ticker: 'AAPL', trader_name: 'Test Trader' }]
        }
      end

      trait :error do
        payload do
          {
            status_code: 500,
            error: 'Internal server error',
            message: 'Database connection failed'
          }
        end
      end

      trait :alpaca_success do
        source { 'alpaca' }
        payload do
          {
            status_code: 200,
            id: 'order-123',
            symbol: 'AAPL',
            qty: 10,
            filled_qty: 10,
            filled_avg_price: 150.25,
            status: 'filled'
          }
        end
      end
    end
  end

  factory :api_call_log, class: 'AuditTrail::ApiCallLog' do
    association :data_ingestion_run
    association :api_request_payload, factory: :api_request
    association :api_response_payload, factory: :api_response
    endpoint { '/api/v1/congressional' }
    http_status_code { 200 }
    duration_ms { 250 }

    trait :failed do
      http_status_code { 500 }
      association :api_response_payload, factory: [:api_response, :error]
    end
  end

  factory :trade_decision, class: 'AuditTrail::TradeDecision' do
    decision_id { SecureRandom.uuid }
    strategy_name { 'CongressionalTradingStrategy' }
    strategy_version { '1.0.0' }
    symbol { 'AAPL' }
    side { 'buy' }
    quantity { 10 }
    order_type { 'market' }
    status { 'pending' }
    decision_rationale do
      {
        signal_strength: 8.5,
        confidence_score: 0.85,
        trigger_event: 'congressional_buy',
        market_context: { current_price: 150.25 }
      }
    end

    trait :executed do
      status { 'executed' }
      executed_at { Time.current }
    end

    trait :failed do
      status { 'failed' }
      failed_at { Time.current }
    end
  end

  factory :trade_execution, class: 'AuditTrail::TradeExecution' do
    association :trade_decision
    execution_id { SecureRandom.uuid }
    association :api_request_payload, factory: [:api_request, :alpaca]
    association :api_response_payload, factory: [:api_response, :alpaca_success]
    status { 'filled' }
    filled_quantity { 10 }
    filled_avg_price { 150.25 }
    alpaca_order_id { 'order-123' }

    trait :rejected do
      status { 'rejected' }
      error_message { 'insufficient buying power' }
      http_status_code { 403 }
      association :api_response_payload, factory: [:api_response, :error]
    end
  end
end
