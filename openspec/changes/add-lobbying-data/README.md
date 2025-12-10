# Add Lobbying Data - Change Summary

**Status**: Draft  
**Priority**: High  
**Timeline**: 2-3 weeks

---

## What This Change Delivers

Adds **Corporate Lobbying Factor Strategy** - a long-term, market-neutral strategy based on lobbying intensity.

### Key Features

1. **Data Integration**
   - Fetch lobbying disclosures from QuiverQuant API
   - Store in new `lobbying_expenditures` table
   - Quarterly aggregation by ticker

2. **Lobbying Intensity Factor**
   - Calculate: `lobbying_spend / market_cap`
   - Normalize to z-scores
   - Rank stocks by intensity

3. **Long/Short Portfolio**
   - Long: Top quintile (highest lobbying)
   - Short: Bottom quintile (lowest lobbying)
   - Market-neutral (50% long, 50% short)
   - Quarterly rebalancing

4. **Automation**
   - Background job for data refresh
   - Quarterly execution (Jan, Apr, Jul, Oct)
   - Rate limit management (1000 calls/day)

---

## Expected Performance

**Academic Research**:
- 5.5-6.7% annual excess return
- $200 market value per $1 lobbying spend
- Multi-year persistence (not subject to alpha decay)

**Risk Profile**:
- Low risk (long-term factor)
- Low turnover (quarterly rebalancing)
- Market-neutral (hedged)

---

## Why Lobbying First?

✅ **API Access Confirmed** - Working endpoint (tested Dec 10)  
✅ **Rich Data** - 1,565+ records for GOOGL alone  
✅ **Academic Backing** - Proven 5.5-6.7% excess returns  
✅ **Uncorrelated** - Different from congressional strategy  
✅ **Low Complexity** - Ticker-specific queries, no bulk processing

**Deferred**: Insider Trading and CNBC (endpoints not found)

---

## Implementation Phases

### Week 1: Data Integration
- Database schema (`lobbying_expenditures`)
- Extend `QuiverClient#fetch_lobbying_data`
- `FetchLobbyingData` command
- `FetchLobbyingDataJob` background job

### Week 2: Strategy Development
- `LobbyingIntensityCalculator` service
- Market cap data integration (Alpaca)
- `GenerateLobbyingFactorPortfolio` command

### Week 3: Testing & Validation
- Unit tests (VCR cassettes)
- Integration tests
- Manual testing with real data
- Paper trading setup

---

## Technical Highlights

### Ticker-Specific API Pattern

```ruby
# Endpoint: /beta/historical/lobbying/{ticker}
# Not bulk - iterate over ticker list

client = QuiverClient.new
data = client.fetch_lobbying_data('GOOGL')
# Returns array of lobbying records
```

### Market-Neutral Portfolio

```ruby
# Generate portfolio
result = TradingStrategies::GenerateLobbyingFactorPortfolio.call(
  quarter: 'Q4 2025',
  long_pct: 0.5,   # 50% of equity
  short_pct: 0.5   # 50% of equity
)

# result[:positions] = [
#   { ticker: 'GOOGL', weight: 5000, reason: 'Long: Top quintile (z=2.4)' },
#   { ticker: 'AAPL', weight: 5000, reason: 'Long: Top quintile (z=2.1)' },
#   { ticker: 'XYZ', weight: -5000, reason: 'Short: Bottom quintile (z=-1.8)' }
# ]
```

---

## Open Questions

1. **Market Cap Source**: Alpaca fundamental data or external API?
2. **Ticker Universe**: S&P 500, Russell 3000, or custom list?
3. **Shorting**: Does Alpaca paper account support shorting?
4. **Benchmark**: What should we compare performance against?

---

## Files

- **Proposal**: `proposal.md` - Full technical specification
- **README**: This file - Quick overview

---

## Next Steps

1. Review and approve proposal
2. Answer open questions
3. Begin Week 1 implementation
4. Set up paper trading environment

---

**Created**: 2025-12-10  
**Author**: Development Team  
**Review By**: [Pending]
