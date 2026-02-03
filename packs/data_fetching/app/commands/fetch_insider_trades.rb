# frozen_string_literal: true

# FetchInsiderTrades Command
#
# Fetches recent insider trades from QuiverQuant and upserts them into the
# quiver_trades table. This command is intentionally focused on the insider
# source only and can be reused by higher-level workflows.
class FetchInsiderTrades < GLCommand::Callable
  allows :start_date, :end_date, :lookback_days, :limit

  returns :total_count, :new_count, :updated_count, :error_count, :error_messages, :record_operations, :api_calls

  def call
    setup_defaults

    client = QuiverClient.new
    trades = fetch_trades(client)
    context.api_calls ||= []
    context.api_calls.concat(client.api_calls)
    context.total_count = trades.size
    context.record_operations ||= []

    process_trades(trades)

    context
  rescue StandardError => e
    context.api_calls.concat(client.api_calls) if client
    stop_and_fail!("Unexpected error: #{e.message}")
  end

  private

  def setup_defaults
    context.lookback_days ||= 60
    context.limit ||= 1000

    context.start_date ||= context.lookback_days.days.ago.to_date
    context.end_date ||= Date.current

    context.new_count = 0
    context.updated_count = 0
    context.error_count ||= 0
    context.error_messages ||= []
    context.api_calls ||= []
  end

  def fetch_trades(client)
    client.fetch_insider_trades(
      start_date: context.start_date,
      end_date: context.end_date,
      limit: context.limit
    )
  end

  def process_trades(trades)
    trades.each do |trade_data|
      next unless valid_trade?(trade_data)

      upsert_trade(trade_data)
    rescue StandardError => e
      context.error_count += 1
      context.error_messages << error_message_for(trade_data, e)
    end
  end

  def valid_trade?(trade_data)
    date = trade_data[:transaction_date]
    return false if date.nil?
    return false if date < context.start_date

    # Filter out non-purchase/sale or unclassified transactions
    transaction_type = trade_data[:transaction_type]
    return false if transaction_type.blank? || transaction_type == 'Other'

    true
  end

  def upsert_trade(trade_data)
    record = QuiverTrade.find_or_initialize_by(
      ticker: trade_data[:ticker],
      transaction_date: trade_data[:transaction_date],
      trader_name: trade_data[:trader_name],
      transaction_type: trade_data[:transaction_type],
      trader_source: 'insider'
    )

    before_changes = record.changed?

    record.company = trade_data[:company]
    record.trade_size_usd = trade_data[:trade_size_usd]
    record.disclosed_at = trade_data[:disclosed_at]
    record.relationship = trade_data[:relationship]
    record.shares_held = trade_data[:shares_held]
    record.ownership_percent = trade_data[:ownership_percent]

    # Only count as updated when attributes actually change
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

  def error_message_for(trade_data, error)
    identifier = [
      trade_data[:ticker],
      trade_data[:trader_name],
      trade_data[:transaction_date]
    ].compact.join(' / ')

    relationship = trade_data[:relationship]
    relationship_info = relationship.present? ? " (relationship=#{relationship.inspect})" : ''

    "#{identifier}#{relationship_info}: #{error.class} - #{error.message}"
  end
end
