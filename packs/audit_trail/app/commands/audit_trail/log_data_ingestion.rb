# frozen_string_literal: true

module AuditTrail
  class LogDataIngestion < GLCommand::Callable
    requires :task_name, :data_source
    allows :ingestion_block
    returns :run

    def self.call(args = {}, &block)
      # If a block is given, pass it as ingestion_block in the arguments
      args = args.merge(ingestion_block: block) if block_given?
      super(**args)
    end

    def call
      run = DataIngestionRun.create!(
        run_id: SecureRandom.uuid,
        task_name: context.task_name,
        data_source: context.data_source,
        started_at: Time.current,
        status: 'running'
      )

      context.run = run

      begin
        # Execute the actual fetch logic
        result = if context.ingestion_block
                   context.ingestion_block.call(run)
                 else
                   {}
                 end

        # Update run with results
        result = {} unless result.is_a?(Hash)
        update_run_success(run, result)

        run.reload
        context
      rescue StandardError => e
        update_run_failure(run, e)
        # GLCommand::Callable's handle_failure will deal with raise_errors option
        raise e
      end
    end

    private

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
      Rails.logger.debug { "DEBUG: LogDataIngestion failed: #{error.message}" }
      Rails.logger.debug error.backtrace.first(10).join("\n")
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
        DataIngestionRunRecord.find_or_create_by!(
          data_ingestion_run: run,
          record: op[:record]
        ) do |record|
          record.operation = op[:operation] # 'created', 'updated', 'skipped'
        end
      end
    end

    def create_api_call_logs(run, result)
      return unless result[:api_calls]

      # Map source to allowed values in ApiPayload
      source = context.data_source.to_s
      source = 'quiverquant' if source.start_with?('quiverquant_')
      source = 'propublica' if source.start_with?('propublica_')

      result[:api_calls].each do |call|
        # Store request/response as ApiPayload (STI)
        request_payload = ApiRequest.create!(
          payload: call[:request],
          source: source,
          captured_at: call[:timestamp] || Time.current
        )

        response_payload = if call[:response]
                             ApiResponse.create!(
                               payload: call[:response],
                               source: source,
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
