# Active Change Proposals

This directory contains active change proposals following the OpenSpec process.

## Priority 1: Enhanced Congressional Trading Strategy

**Change ID**: `add-enhanced-congressional-strategy`  
**Status**: COMPLETED (archived as of 2025-11-11)  
**Effort**: 2-3 weeks  
**Tasks**: 91/91 complete (see archive/2025-11-11-add-enhanced-congressional-strategy)

### What
Enhance the simple congressional trading strategy with:
- Committee oversight filtering
- Politician quality scoring (historical track record)
- Consensus trade detection
- Dynamic position sizing

### Expected Impact
- +3-5% annual alpha improvement
- Sharpe ratio: -1.26 → >0.5
- Maintains low risk (max drawdown <5%)

### Dependencies
- ProPublica Congress API key (free)
- 5 new database models
- 5 new services

---

## Priority 2: Corporate Insider Trading Strategy

**Change ID**: `add-corporate-insider-strategy`  
**Status**: In Progress  
**Effort**: 3-4 weeks  
**Tasks**: 16/99 complete

### What
Complete Strategy #1 from roadmap by adding corporate insider trading:
- CEO, CFO, Director trades
- Role-weighted position sizing
- 2-day disclosure lag (faster than congressional)
- Multi-strategy framework (run both strategies in parallel)

### Expected Impact
- 5-7% annual alpha (proven in research)
- Lower correlation with congressional strategy
- Diversification benefit (faster signals)

### Dependencies
- QuiverQuant Tier 2 subscription (insider trading endpoint)
- 3 new columns on quiver_trades table
- Multi-strategy execution framework

---

## Commands

```bash
# View proposals
openspec list
openspec show add-enhanced-congressional-strategy
openspec show add-corporate-insider-strategy

# Validate
openspec validate add-enhanced-congressional-strategy --strict
openspec validate add-corporate-insider-strategy --strict

# After approval, start implementation
# Follow tasks.md in each change directory
```

---

## Priority 3: Corporate Insider Consensus Detection

**Change ID**: `add-insider-consensus-detection`  
**Status**: Draft - Awaiting Approval  
**Effort**: 2-3 weeks  
**Tasks**: 0/91 complete  
**Prerequisites**: Requires Priority 2 (`add-corporate-insider-strategy`) completed first

### What
Enhance the basic insider strategy with consensus detection:
- Detect when 2+ insiders from same company buy within 30 days
- Calculate conviction scores (0-10) based on insider seniority + transaction size
- Boost position sizes for consensus stocks (1.5-2.0x multiplier)
- Flag CEO's first-ever purchases (high signal)
- Detect cross-company clustering (multiple companies → same stock)

### Expected Impact
- +2-4% annual alpha over basic insider strategy
- Better identification of high-conviction signals
- Improved risk-adjusted returns

### Dependencies
- **Requires**: `add-corporate-insider-strategy` (Priority 2) completed
- 3 new services (consensus detection, conviction scoring, behavioral shifts)
- 1 database migration (consensus tracking fields)

---

## Backlog: Government Contracts Strategy

**Change ID**: `add-government-contracts-strategy`  
**Status**: Draft - Backlog  
**Effort**: 3-4 weeks  
**Tasks**: 0/120 complete

### What
Event-driven strategy based on government contract awards:
- Fetch contract awards from QuiverQuant
- Assess materiality (contract value as % of company revenue)
- Time-based exits (5-10 day holding periods)
- Sector-specific thresholds (defense: 0.5%, tech: 2%)
- Track performance by awarding agency (DoD, NASA, etc.)

### Expected Impact
- Positive CAR (cumulative abnormal returns) on contract announcements
- Particularly strong for defense/aerospace sector
- Uncorrelated with insider strategies (different timing)

### Dependencies
- QuiverQuant Tier 2 subscription (gov contracts endpoint)
- **NEW**: Fundamental data source for company revenue
  - Alpaca fundamentals OR external API (FMP, Alpha Vantage)
  - OR hardcoded revenue for top 100 contractors (MVP)
- 1 new database table (government_contracts)
- FundamentalDataService (new)

### Complexity Notes
- Higher complexity due to fundamental data requirement
- Materiality assessment adds logic complexity
- Time-based exits require position tracking enhancement
- Consider after Priorities 1-3 are stable

---

## Next Steps

1. Review all proposals (3 priorities + 1 backlog)
2. Prioritize implementation order (recommended: Priority 1 → 2 → 3 → Backlog)
3. Approve selected proposal
4. Begin implementation following tasks.md
5. After deployment, archive with: `openspec archive <change-id> --yes`
