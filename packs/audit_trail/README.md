# Audit Trail Pack

Provides comprehensive auditability and traceability for the trading system, implementing the outbox pattern for trade decisions and centralized logging for data ingestion and API interactions.

## Key Capabilities

1.  **Data Ingestion Audit Trail**: Logs every rake task execution, tracking records fetched/created/updated and linking them to specific ingestion runs.
2.  **Trade Decision Outbox Pattern**: Captures trade intent and complete decision rationale (signals, market context) BEFORE execution.
3.  **Trade Execution Logging**: Logs all Alpaca API interactions (request/response) and links them to trade decisions.
4.  **Centralized API Payload Storage**: Stores all API request/response pairs using Single Table Inheritance (STI).

## Technical Components

### Models

*   `AuditTrail::DataIngestionRun`: Tracks execution of data fetching tasks.
*   `AuditTrail::DataIngestionRunRecord`: Junction record linking ingested models to runs.
*   `AuditTrail::ApiPayload`: Base STI class for API request/response storage.
*   `AuditTrail::ApiCallLog`: Links API payloads to ingestion runs.
*   `AuditTrail::TradeDecision`: Stores trade intent and rationale (the "Outbox").
*   `AuditTrail::TradeExecution`: Tracks actual execution results and API calls.

### Commands

*   `AuditTrail::LogDataIngestion`: Wrapper for logging data ingestion logic.
*   `AuditTrail::CreateTradeDecision`: Creates a pending trade decision with data lineage.
*   `AuditTrail::ExecuteTradeDecision`: Synchronously executes a trade and logs API interaction.

## Usage

### Logging Data Ingestion

```ruby
AuditTrail::LogDataIngestion.call(
  task_name: 'data_fetch:congress_daily',
  data_source: 'quiverquant_congress'
) do |run|
  # Fetch data and return counts/operations
  {
    fetched: 10,
    created: 8,
    updated: 2,
    record_operations: [...]
  }
end
```

### Creating a Trade Decision

```ruby
decision_cmd = AuditTrail::CreateTradeDecision.call(
  strategy_name: 'CongressionalTradingStrategy',
  symbol: 'AAPL',
  side: 'buy',
  quantity: 100,
  rationale: { signal_strength: 9.5, ... }
)
```

## Documentation

See `/docs/architecture/trade-outbox-pattern/` for detailed technical specifications.
