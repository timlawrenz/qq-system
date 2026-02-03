# frozen_string_literal: true

# FetchGovernmentContracts
#
# Fetches recent government contract awards from QuiverQuant and upserts them into the
# government_contracts table.
class FetchGovernmentContracts < GLCommand::Callable
  allows :start_date, :end_date, :lookback_days, :limit, :tickers, :max_tickers

  returns :total_count, :new_count, :updated_count, :error_count, :error_messages, :record_operations, :api_calls

  def call
    setup_defaults

    client = QuiverClient.new
    contracts = fetch_contracts(client)
    context.api_calls = client.api_calls
    context.total_count = contracts.size
    context.record_operations = []

    process_contracts(contracts)

    context
  rescue StandardError => e
    context.api_calls = client.api_calls if client
    stop_and_fail!("Unexpected error: #{e.message}")
  end

  private

  def setup_defaults
    context.lookback_days ||= 90
    context.limit ||= 1000
    context.max_tickers ||= 25

    context.start_date ||= context.lookback_days.days.ago.to_date
    context.end_date ||= Date.current

    context.new_count = 0
    context.updated_count = 0
    context.error_count = 0
    context.error_messages = []
    context.api_calls = []
  end

  def fetch_contracts(client)
    # If you want more than the last quarter, you must supply tickers and use the
    # historical endpoint (Quiver live endpoint is last-quarter only).
    if use_historical_fetch?
      tickers = Array(context.tickers).presence || default_tickers
      tickers = tickers.compact.map { |t| t.to_s.upcase }.uniq.first(context.max_tickers)

      if tickers.empty?
        Rails.logger.warn('[FetchGovernmentContracts] No tickers available for govcontracts historical fetch')
        return []
      end

      return tickers.flat_map do |ticker|
        client.fetch_government_contracts(
          ticker: ticker,
          start_date: context.start_date,
          end_date: context.end_date,
          limit: context.limit
        )
      rescue StandardError => ticker_error
        context.error_count += 1
        context.error_messages << "FETCH #{ticker}: #{ticker_error.message}"
        []
      end
    end

    client.fetch_government_contracts
  end

  def use_historical_fetch?
    context.tickers.present? || context.lookback_days.to_i > 120
  end

  def default_tickers
    QuiverTrade
      .where(trader_source: %w[congress insider])
      .purchases
      .recent(30)
      .distinct
      .limit(context.max_tickers)
      .pluck(:ticker)
  end

  def process_contracts(contracts)
    contracts.each do |contract_data|
      next unless valid_contract?(contract_data)

      upsert_contract(contract_data)
    rescue StandardError => e
      context.error_count += 1
      context.error_messages << error_message_for(contract_data, e)
    end
  end

  def valid_contract?(contract_data)
    date = contract_data[:award_date]
    return false if date.nil?
    return false if date < context.start_date

    value = contract_data[:contract_value]
    return false if value.nil? || value.to_d <= 0

    contract_data[:ticker].present? && contract_data[:contract_id].present?
  end

  def upsert_contract(contract_data)
    record = GovernmentContract.find_or_initialize_by(contract_id: contract_data[:contract_id])

    before_changes = record.changed?

    record.ticker = contract_data[:ticker]
    record.company = contract_data[:company]
    record.contract_value = contract_data[:contract_value]
    record.award_date = contract_data[:award_date]
    record.agency = contract_data[:agency]
    record.contract_type = contract_data[:contract_type]
    record.description = contract_data[:description]
    record.disclosed_at = contract_data[:disclosed_at]

    if record.new_record?
      record.save!
      context.new_count += 1
      context.record_operations << { record: record, operation: 'created' }
    elsif record.changed? || before_changes
      record.save!
      context.updated_count += 1
      context.record_operations << { record: record, operation: 'updated' }
    else
      context.record_operations << { record: record, operation: 'skipped' }
    end
  end

  def error_message_for(contract_data, error)
    identifier = [
      contract_data[:contract_id],
      contract_data[:ticker],
      contract_data[:award_date]
    ].compact.join(' / ')

    "#{identifier}: #{error.class} - #{error.message}"
  end
end
