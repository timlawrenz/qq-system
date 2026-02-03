# QuiverQuant Insider API Field Mapping

**Endpoint**: `/beta/live/insiders`  
**Documentation**: https://api.quiverquant.com/docs/#/operations/beta_live_insiders_retrieve  
**Date Discovered**: December 11, 2025

---

## Actual API Response Format

```json
{
  "Ticker": "NUS",
  "Date": "2025-12-10T00:00:00.000",
  "Name": "WOODBURY EDWINA D",
  "AcquiredDisposedCode": "A",       // A = Acquired, D = Disposed
  "TransactionCode": "A",             // P = Purchase, S = Sale, A = Award/Grant
  "Shares": 10.0,
  "PricePerShare": 10.35,
  "SharesOwnedFollowing": 42979.0,
  "fileDate": "2025-12-11T21:44:37.000",
  "officerTitle": "Executive Chair, CEO & Pres.",  // Can be null
  "isDirector": true,
  "isOfficer": false,
  "isTenPercentOwner": false,
  "isOther": false,
  "directOrIndirectOwnership": "D",
  "uploaded": "2025-12-11T21:45:26.820"
}
```

---

## Field Mapping to quiver_trades

| API Field | Database Field | Transformation |
|-----------|----------------|----------------|
| `Ticker` | `ticker` | Direct |
| `Name` | `trader_name` | Direct |
| `Date` | `transaction_date` | Parse date |
| `fileDate` | `disclosed_at` | Parse datetime |
| `AcquiredDisposedCode` | `transaction_type` | **A → Purchase, D → Sale** |
| `Shares * PricePerShare` | `trade_size_usd` | Calculate |
| `SharesOwnedFollowing` | `shares_held` | Direct |
| `officerTitle` OR flags | `relationship` | See relationship logic |
| N/A | `trader_source` | Hardcoded: 'insider' |
| N/A | `company` | Not provided, set to nil |
| N/A | `ownership_percent` | Not calculated (can add later) |

---

## Transaction Type Logic

```ruby
def determine_transaction_type(acquired_disposed, transaction_code)
  case acquired_disposed
  when 'A'
    'Purchase'  # Acquired = Purchase
  when 'D'
    'Sale'      # Disposed = Sale
  else
    # Fallback to transaction code
    case transaction_code
    when 'P' then 'Purchase'
    when 'S' then 'Sale'
    else 'Other'
    end
  end
end
```

**Key Codes**:
- **AcquiredDisposedCode**: `A` = Acquired, `D` = Disposed
- **TransactionCode**: `P` = Purchase, `S` = Sale, `A` = Award/Grant, `M` = Exercise

---

## Relationship Logic

```ruby
def determine_relationship(trade)
  title = trade['officerTitle']
  return title if title.present?

  # Build relationship from flags
  relationships = []
  relationships << 'Director' if trade['isDirector']
  relationships << 'Officer' if trade['isOfficer']
  relationships << '10% Owner' if trade['isTenPercentOwner']

  relationships.any? ? relationships.join(', ') : 'Other'
end
```

**Examples**:
- `officerTitle: "Executive Chair, CEO & Pres."` → `"Executive Chair, CEO & Pres."`
- `isDirector: true, isOfficer: false` → `"Director"`
- `isDirector: true, isOfficer: true` → `"Director, Officer"`

---

## Executive Detection for Strategy Filter

The `GenerateInsiderMimicryPortfolio` filters for executives using:

```ruby
executive_titles = %w[CEO CFO President Chief]

trades.select do |trade|
  next false if trade.relationship.blank?
  
  executive_titles.any? { |title| trade.relationship.include?(title) }
end
```

**Matches**:
- ✅ "Executive Chair, CEO & Pres." (contains "CEO", "President", "Chief")
- ✅ "Chief Financial Officer" (contains "Chief")
- ✅ "President" (exact match)
- ❌ "Director" (no executive keyword)
- ❌ "10% Owner" (no executive keyword)

---

## Trade Value Calculation

```ruby
shares = trade['Shares'].to_f        # 10.0
price = trade['PricePerShare'].to_f  # 10.35
trade_value = shares * price         # 103.5

{
  trade_size_usd: trade_value.to_s  # "103.5"
}
```

---

## Known Limitations

1. **No Company Name**: API doesn't return company name, only ticker
2. **Ownership Percent**: Not provided, would need to calculate from SharesOwnedFollowing + outstanding shares data
3. **Transaction Purpose**: SEC Form 4 sometimes includes purpose (retirement plan, estate planning, etc.) but not in this endpoint

---

## Comparison to Congressional Trades

| Field | Congressional API | Insider API |
|-------|------------------|-------------|
| Trader Name | `Name` | `Name` |
| Transaction Type | `Transaction` | **Must derive from AcquiredDisposedCode** |
| Amount | `Trade_Size_USD` (direct) | **Must calculate: Shares × Price** |
| Relationship | N/A (politician) | `officerTitle` + flags |
| Disclosure | `Filed` | `fileDate` |

**Key Difference**: Congressional API provides `Transaction: "Purchase"` directly, but Insider API uses codes that must be translated.

---

## Example Parsed Output

```ruby
{
  ticker: "NUS",
  company: nil,
  trader_name: "WOODBURY EDWINA D",
  trader_source: "insider",
  transaction_date: Wed, 10 Dec 2025,
  transaction_type: "Purchase",
  trade_size_usd: "103.5",
  disclosed_at: 2025-12-11 21:44:37 UTC,
  relationship: "Director",
  shares_held: 42979,
  ownership_percent: nil
}
```

---

## Testing Commands

```bash
# Fetch and parse insider trades
bundle exec rails runner "
  client = QuiverClient.new
  trades = client.fetch_insider_trades(limit: 5)
  trades.each do |t|
    puts \"#{t[:ticker]}: #{t[:transaction_type]} by #{t[:relationship]} - \$#{t[:trade_size_usd]}\"
  end
"

# Save to database
bundle exec rails runner "
  client = QuiverClient.new
  trades = client.fetch_insider_trades(limit: 10)
  
  trades.each do |trade_data|
    QuiverTrade.create!(
      ticker: trade_data[:ticker],
      transaction_date: trade_data[:transaction_date],
      trader_name: trade_data[:trader_name],
      transaction_type: trade_data[:transaction_type],
      trader_source: 'insider',
      company: trade_data[:company],
      trade_size_usd: trade_data[:trade_size_usd],
      disclosed_at: trade_data[:disclosed_at],
      relationship: trade_data[:relationship],
      shares_held: trade_data[:shares_held],
      ownership_percent: trade_data[:ownership_percent]
    )
  end
  
  puts \"Saved #{trades.size} insider trades\"
"
```

---

**Status**: ✅ Field mapping verified and implemented  
**Last Updated**: December 11, 2025  
**Related**: `packs/data_fetching/app/services/quiver_client.rb` (lines 215-279)
