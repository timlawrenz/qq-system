# frozen_string_literal: true

module AuditTrail
  class LogDataIngestion
    attr_reader :task_name, :data_source, :run

    def initialize(task_name:, data_source:)
      @task_name = task_name
      @data_source = data_source
    end

    def call(&block)
      @run = create_run_record

      begin
        # Execute the actual fetch logic (passed as block)
        result = block_given? ? yield(@run) : {}

        # Update run with results (ensure result is a hash)
        result = {} unless result.is_a?(Hash)
        update_run_success(@run, result)

        @run.reload
        true

      rescue StandardError => e
        update_run_failure(@run, e)
        false
      end
    end

    def success?
      return nil unless @run
      
      @run.status == 'completed'
    end

    private

    def create_run_record
      DataIngestionRun.create!(
        run_id: SecureRandom.uuid,
        task_name: @task_name,
        data_source: @data_source,
        started_at: Time.current,
        status: 'running'
      )
    end

    def update_run_success(run, result)
      run.update!(
        completed_at: Time.current,
        status: 'completed',
        records_fetched: result[:fetched] || 0,
        records_created: result[:created] || 0,
        records_updated: result[:updated] || 0,
        records_skipped: result[:skipped] || 0,
        data_date_start: result[:date_range]&.first,
        data_date_end: result[:date_range]&.last
      )

      # Create junction records
      create_run_records(run, result)

      # Create API call logs
      create_api_call_logs(run, result)

      Rails.logger.info("✅ #{run.task_name} completed: #{result[:created]} new, #{result[:updated]} updated")
    end

    def update_run_failure(run, error)
      run.update!(
        failed_at: Time.current,
        status: 'failed',
        error_message: error.message,
        error_details: {
          backtrace: error.backtrace&.first(10),
          class: error.class.name
        }
      )

      Rails.logger.error("❌ #{run.task_name} failed: #{error.message}")
    end

    def create_run_records(run, result)
      return unless result[:record_operations]

      result[:record_operations].each do |op|
        DataIngestionRunRecord.create!(
          data_ingestion_run: run,
          record: op[:record],
          operation: op[:operation] # 'created', 'updated', 'skipped'
        )
      end
    end

    def create_api_call_logs(run, result)
      return unless result[:api_calls]

      result[:api_calls].each do |call|
        # Store request/response as ApiPayload (STI)
        request_payload = ApiRequest.create!(
          payload: call[:request],
          source: @data_source,
          captured_at: call[:timestamp] || Time.current
        )

        response_payload = if call[:response]
                             ApiResponse.create!(
                               payload: call[:response],
                               source: @data_source,
                               captured_at: call[:timestamp] || Time.current
                             )
                           end

        ApiCallLog.create!(
          data_ingestion_run: run,
          api_request_payload: request_payload,
          api_response_payload: response_payload,
          endpoint: call[:endpoint],
          http_status_code: call[:status_code],
          duration_ms: call[:duration_ms],
          rate_limit_remaining: call[:rate_limit_remaining]
        )
      end
    end
  end
end
