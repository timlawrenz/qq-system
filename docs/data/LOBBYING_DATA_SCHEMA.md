# Lobbying Data Schema - Real API Response

**Date Discovered**: December 10, 2025  
**Source**: Quiver API `/beta/historical/lobbying/{ticker}`  
**Sample Tickers Tested**: GOOGL, AAPL, JPM

---

## API Response Structure

The Quiver API returns a **JSON array** of lobbying disclosure records.

### Response Fields

From actual API data (GOOGL, AAPL, JPM):

```ruby
{
  ticker: "GOOGL",                    # Added by our client (not in API)
  date: Date<2025-10-21>,            # Parsed from "Date" field
  quarter: "Q4 2025",                # Extracted or calculated from date
  amount: 45000.0,                   # Parsed from "Amount" field
  client: "GOOGLE CLIENT SERVICES",   # "Client" field
  issue: "Consumer Issues/Safety/Products\nTelecommunications\nCopyright/Patent/Trademark...",
  specific_issue: "Issues pertaining to technology and consumer protection issues...",
  registrant: "THE MADISON GROUP"    # Lobbying firm name
}
```

### Actual API Fields (Raw JSON)

```json
{
  "Date": "2025-10-21",
  "Amount": "45000.0",
  "Client": "GOOGLE CLIENT SERVICES",
  "Issue": "Consumer Issues/Safety/Products \n Telecommunications \n Copyright/Patent/Trademark...",
  "Specific_Issue": "Issues pertaining to technology and consumer protection issues...",
  "Registrant": "THE MADISON GROUP",
  "Ticker": "GOOGL"  // Sometimes present
}
```

**Note**: The `Quarter` field may or may not be present in the API response. Our client calculates it from the date if missing.

---

## Data Characteristics

### Historical Depth

**GOOGL** (1,565 records):
- Date range: 2003-06-23 to 2025-10-21 (22+ years)
- Total spending: $305,339,377
- Average per disclosure: $195,230

**AAPL** (362 records):
- Date range: 1999-08-16 to 2025-10-20 (26+ years)
- Total spending: $134,185,689
- Average per disclosure: $370,679

**JPM** (376 records):
- Date range: 1999-08-16 to 2025-10-20 (26+ years)
- Total spending: $86,506,405
- Average per disclosure: $230,070

### Quarter Coverage

All tested tickers have quarterly data from late 1990s/early 2000s through Q4 2025.

**Example quarters** (GOOGL): Q1-Q4 for years 2005-2025, with some gaps in early years.

---

## Data Quality Observations

### Good

1. **Rich Historical Data**: 20+ years of lobbying disclosures
2. **Quarterly Consistency**: Regular quarterly filings (as required by law)
3. **Detailed Metadata**: Client, registrant, issues, specific issues all populated
4. **Current Data**: Most recent data is Q4 2025 (very recent)

### Considerations

1. **Zero Amounts**: Some records have `amount: 0.0` (e.g., JPM Q4 2025 record)
   - May indicate filing corrections or amendments
   - Should handle gracefully in aggregations

2. **Text Fields**: Issue and specific_issue can be very long (100+ characters)
   - Contains newlines and multiple topics
   - Good for search/analysis, need TEXT column type

3. **Multiple Registrants**: Same ticker/quarter can have multiple lobbying firms
   - Each firm files separately
   - Need to aggregate by quarter for "total lobbying spend"

4. **Early Data Gaps**: Some quarters missing in early 2000s
   - Companies weren't lobbying, or data not digitized
   - Not a data quality issue

---

## Database Schema Recommendations

Based on actual data structure:

```ruby
create_table :lobbying_expenditures do |t|
  # Identifiers
  t.string :ticker, null: false, index: true
  t.string :quarter, null: false, index: true       # "Q4 2025"
  t.date :date, null: false                         # Actual filing date
  
  # Financial
  t.decimal :amount, precision: 15, scale: 2, default: 0.0
  
  # Metadata (can be duplicated across same ticker/quarter)
  t.string :client                                  # "GOOGLE CLIENT SERVICES"
  t.string :registrant                              # Lobbying firm name
  t.text :issue                                     # Long text, newlines
  t.text :specific_issue                            # Very long text
  
  t.timestamps
  
  # Unique constraint: One record per ticker/quarter/registrant
  # (A company can use multiple lobbying firms per quarter)
  t.index [:ticker, :quarter, :registrant], unique: true, name: 'idx_lobbying_unique'
  t.index [:ticker, :quarter]
  t.index :date
end
```

### Why `registrant` in unique index?

Looking at the data, a single company (e.g., GOOGL) in a single quarter (e.g., Q4 2025) may file disclosures through multiple lobbying firms:
- "THE MADISON GROUP" - $45,000
- "FEDERAL STREET STRATEGIES" - $30,000
- etc.

Each registrant (lobbying firm) files separately with their own amount.

To get **total quarterly spending for a ticker**, we need to **SUM amounts** across all registrants:

```ruby
LobbyingExpenditure
  .where(ticker: 'GOOGL', quarter: 'Q4 2025')
  .sum(:amount)
```

---

## Quarterly Aggregation Strategy

For the lobbying intensity factor, we need quarterly totals:

```ruby
# Get quarterly total for each ticker
def self.quarterly_totals(quarter)
  where(quarter: quarter)
    .group(:ticker)
    .sum(:amount)
end

# Returns: { 'GOOGL' => 305000.0, 'AAPL' => 150000.0, ... }
```

This aggregates across all registrants/clients for each ticker in that quarter.

---

## API Integration Notes

### Rate Limiting

With 1,000 calls/day limit:
- Can fetch 1,000 tickers per day
- S&P 500 universe: Takes 1 day
- Russell 3000 universe: Takes 3 days

**Strategy**: Batch processing over multiple days for initial backfill.

### Error Handling

**404 Response**: Not an error, just means ticker has no lobbying data
```ruby
# Client returns [] for 404, which is correct behavior
data = client.fetch_lobbying_data('TICKER')  # => []
```

**Expected for**:
- Small companies (don't lobby)
- Non-tech/non-finance sectors (less lobbying)
- New companies (no historical data yet)

---

## Sample Queries

### Total Lobbying by Ticker (All Time)

```ruby
LobbyingExpenditure
  .group(:ticker)
  .sum(:amount)
  .sort_by { |_, amount| -amount }
  .first(10)

# Top 10 lobbying spenders
```

### Quarterly Trend for Single Ticker

```ruby
LobbyingExpenditure
  .where(ticker: 'GOOGL')
  .group(:quarter)
  .sum(:amount)
  .sort_by { |q, _| q }

# Shows quarterly spending over time
```

### Most Active Lobbying Firms

```ruby
LobbyingExpenditure
  .group(:registrant)
  .count
  .sort_by { |_, count| -count }
  .first(10)

# Which firms file the most disclosures?
```

---

## Next Steps

1. ✅ **DONE**: Extend QuiverClient with `fetch_lobbying_data(ticker)`
2. **TODO**: Create database migration with schema above
3. **TODO**: Create LobbyingExpenditure model
4. **TODO**: Create FetchLobbyingData command to persist records
5. **TODO**: Add VCR tests with real API responses

---

**Status**: ✅ API Integration Complete  
**Client Method**: `QuiverClient#fetch_lobbying_data(ticker)`  
**Test Results**: Working perfectly with GOOGL (1,565 records), AAPL (362 records), JPM (376 records)
