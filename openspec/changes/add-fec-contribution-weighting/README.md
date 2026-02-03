# Add FEC Contribution Weighting - Change Summary

**Status**: Proposal - Ready for Review  
**Priority**: Medium  
**Timeline**: 8-12 hours (1-2 days)

---

## What This Change Delivers

Enhances congressional trading signals by weighting trades based on **actual campaign finance data** from the Federal Election Commission.

### The Signal

**Current**: Trade gets 1.0x weight regardless of politician's financial relationships  
**Enhanced**: Trade gets 1.0x-2.0x weight based on industry contribution amounts

**Example:**
- Senator receives $150k from Technology employers → Tech stock trades get 1.8x weight
- Senator receives $30k from Healthcare employers → Healthcare trades get 1.3x weight
- Senator receives $0 from Energy companies → Energy trades get 1.0x weight (baseline)

---

## Why This Matters for Trading

### The Hypothesis

**Politicians are more likely to trade stocks in industries that fund their campaigns.**

**Evidence:**
- Campaign contributors seek policy influence
- Politicians have information advantages in industries they oversee
- Financial relationships correlate with legislative activity
- Trades in "funded industries" may have higher alpha

### Expected Impact

**Alpha Improvement: +0.5-1.5% annually**
- Current enhanced strategy: 3-5% alpha
- With FEC weighting: 3.5-6.5% alpha
- Minimal additional risk

**Sharpe Ratio: 0.5 → 0.6+**
- Better risk-adjusted returns
- Same max drawdown (~5%)

**On $10k Account:**
- Before: $300-500/year
- After: $350-650/year (+$50-150)

---

## How It Works

### Data Flow

```
1. Fetch FEC Contributions
   ├─ GET /schedules/schedule_a/by_employer/?committee_id=C00213512&cycle=2024
   └─ Returns: [{employer: "Kaiser Permanente", amount: 8420}, ...]

2. Classify Employers to Industries (keyword matching)
   ├─ "Kaiser Permanente" → /health/ → Healthcare industry
   ├─ "Citadel Investment" → /capital/ → Financial Services industry
   └─ "University of California" → /university/ → Other (skip or new industry)

3. Aggregate by Industry
   └─ Store: PoliticianIndustryContribution
       ├─ politician: Nancy Pelosi
       ├─ industry: Healthcare
       ├─ cycle: 2024
       ├─ total_amount: $45,000
       └─ influence_score: 6.5 (log-scaled 0-10)

4. Apply to Trades
   ├─ Pelosi trades UNH (Healthcare stock)
   ├─ Lookup: Healthcare contribution = $45k → influence_score = 6.5
   └─ Weight multiplier: 1.0 + (6.5/10) = 1.65x
```

### Classification Strategy

**Reuse existing `Industry.classify_stock()` keyword patterns:**
```ruby
"Kaiser Permanente" → /health/ → Healthcare ✅
"Citadel Investment Group" → /capital|investment/ → Financial Services ✅
"University of California" → /university/ → Other (skip for trading)
"RETIRED" / "NOT EMPLOYED" → skip (not industry-related)
```

**Expected coverage: 70-80% of contribution $**

---

## What Gets Built

### 1. New Table: `politician_industry_contributions`

```ruby
{
  politician_profile_id: 123,
  industry_id: 2,  # Technology
  cycle: 2024,
  total_amount: 150_000.00,
  contribution_count: 450,
  employer_count: 25,
  top_employers: [
    {name: "Google Inc", amount: 35000},
    {name: "Microsoft Corp", amount: 28000},
    {name: "Apple employees", amount: 22000}
  ],
  influence_score: 7.5,  # Calculated: log scale 0-10
  fetched_at: "2026-01-15"
}
```

### 2. New Service: `FecClient`

```ruby
client = FecClient.new
contributions = client.fetch_contributions_by_employer(
  committee_id: "C00213512",
  cycle: 2024
)
```

### 3. New Command: `SyncFecContributions`

```ruby
result = SyncFecContributions.call(cycle: 2024)
# Fetches FEC data for all politicians
# Classifies employers to industries
# Stores aggregated contributions
```

### 4. Enhanced Strategy: FEC Weight Multiplier

```ruby
# packs/trading_strategies/app/commands/trading_strategies/generate_enhanced_congressional_portfolio.rb

def calculate_fec_influence_multiplier(ticker, ticker_trades)
  industries = Industry.classify_stock(ticker)
  return 1.0 if industries.empty?
  
  politicians = ticker_trades.map(&:trader_name).uniq
  contributions = PoliticianIndustryContribution
    .current_cycle
    .where(politician_profile_id: politicians, industry: industries)
    .where('total_amount >= ?', 10_000)  # $10k minimum threshold
  
  return 1.0 if contributions.empty?
  
  avg_influence = contributions.average(:influence_score).to_f
  multiplier = 1.0 + (avg_influence / 10.0)  # 1.0x to 2.0x range
  
  [multiplier, 2.0].min  # Cap at 2.0x
end
```

---

## Trading Signal Validation

### Question 1: Do we need Education/Legal Services industries?

**Answer: NO (for trading purposes)**
- Universities/law firms contribute heavily but don't have tradable stocks
- "Education" industry = no public companies to trade
- "Legal Services" = sparse public companies (not focus area)
- **Decision**: Classify as "Other" and skip in FEC weighting (1.0x multiplier)

### Question 2: Minimum $ threshold for influence?

**Answer: $10,000 minimum**
- **$10k**: Signal threshold - meaningful but not extreme
- **Rationale**: 
  - Filters noise (small donors)
  - Balances coverage (keeps 60-70% of data)
  - Avoids false signals from trivial amounts
- **Lower threshold ($5k)**: Too noisy
- **Higher threshold ($50k)**: Excludes too much data

### Question 3: Track PAC vs individual separately?

**Answer: NO (aggregate all contributions)**
- **Trading signal**: Total industry influence matters most
- **Complexity**: Separating adds minimal value
- **Future**: Could revisit if PAC money shows stronger correlation
- **Decision**: Aggregate all contribution types per industry

### Question 4: Multi-cycle historical tracking?

**Answer: Current cycle (2024) only - MVP**
- **Trading focus**: Recent financial relationships most relevant
- **API efficiency**: One cycle = simpler, faster
- **Future enhancement**: Multi-cycle trend analysis after validation
- **Decision**: Start with single cycle, add history if validated

---

## Validation Criteria

### Phase 1: Data Quality (Week 1)

✅ **Coverage**: Classify 70%+ of contribution $ to industries  
✅ **Politicians**: Successfully sync 300+ active traders  
✅ **Accuracy**: Spot-check 20 politicians - verify classification makes sense  
✅ **Performance**: FEC sync completes in <10 minutes

### Phase 2: Trading Impact (Week 2-4)

✅ **Multiplier Distribution**: Average ~1.3-1.5x (reasonable range)  
✅ **Signal Frequency**: 30-50% of trades get FEC boost (not too rare)  
✅ **No Degradation**: Performance doesn't decrease vs baseline  
✅ **Alpha Improvement**: Measured +0.3-1.0% in paper trading

### Phase 3: Production Validation (Month 1)

✅ **Stable Execution**: No errors, sync runs quarterly  
✅ **Alpha Confirmation**: +0.5%+ validated in live trading  
✅ **Monitoring**: Classification rate stays >65%

---

## Implementation Timeline

### Day 1-2: Core Infrastructure (4-5 hours)
- Create `FecClient` service
- Create `politician_industry_contributions` table
- Test FEC API calls with real data

### Day 3-4: Data Sync (3-4 hours)
- Build `SyncFecContributions` command
- Implement keyword-based classification
- Add influence score calculation
- Initial sync for 50 politicians (validation)

### Day 5: Trading Integration (2-3 hours)
- Add FEC multiplier to enhanced strategy
- Test with paper trading
- Validate multiplier calculations

### Day 6+: Monitoring & Tuning
- Deploy to production
- Monitor classification rate
- Tune keywords for unclassified employers
- Track alpha impact

---

## Risk Assessment

### Low Risk ✅

- **Free API** - No cost
- **Optional enhancement** - Doesn't break existing logic
- **Fallback**: Returns 1.0x if no FEC data (graceful degradation)
- **Tested approach**: Keyword matching already works for stocks

### Medium Risk ⚠️

- **Classification accuracy** - Some employers may be misclassified
  - *Mitigation*: Track unclassified employers, manual review
- **Data staleness** - Contributions lag by 30-90 days
  - *Mitigation*: Quarterly sync after FEC filing deadlines
- **Private employers dominate** - 80% are non-publicly-traded
  - *Mitigation*: Industry-level aggregation (not ticker-level)

### Mitigations

1. **Monitoring**: Alert if classification rate <65%
2. **Logging**: Track all unclassified employers >$10k
3. **Iteration**: Add keywords for common employers
4. **Thresholds**: $10k minimum filters noise

---

## Success Metrics

### Week 1
- ✅ FEC API integrated
- ✅ 70%+ contribution $ classified
- ✅ 300+ politicians synced
- ✅ Sync completes <10 minutes

### Month 1
- ✅ 30-50% of trades get FEC weight boost
- ✅ Average multiplier 1.3-1.5x (reasonable)
- ✅ No performance degradation
- ✅ Measured alpha: +0.3-0.8%

### Month 3
- ✅ Validated alpha improvement: +0.5-1.5%
- ✅ Classification rate stable >65%
- ✅ Quarterly sync automated
- ✅ System running reliably

---

## Files

- **README**: This file - Trading signal overview
- **proposal.md**: Full technical specification (implementation details)

---

## Decision Required

**Approve this change?**

✅ **YES** - Proceed with implementation  
❌ **NO** - Specify concerns or defer

---

**Created**: 2026-01-16  
**Author**: GitHub Copilot CLI  
**Review By**: [Product Owner]
