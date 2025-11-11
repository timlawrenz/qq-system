# Change Proposal: Government Contracts Strategy

**Change ID**: `add-government-contracts-strategy`  
**Type**: Feature Addition  
**Status**: ⏸️ BLOCKED - Subscription Required  
**Priority**: Medium (Backlog - Priority 5 in roadmap)  
**Estimated Effort**: 3-4 weeks  
**Created**: 2025-11-10  
**Blocked Date**: 2025-11-11  
**Blocker**: QuiverQuant subscription tier does not include government contracts data  

---

## ⚠️ Current Blocker (Nov 11, 2025)

**Tested Endpoints**:
- `/beta/live/govcontracts` - **500 Server Error** (endpoint exists but access unclear)
- `/beta/bulk/govcontracts` - **404 Not Found**
- Other variations - **404 Not Found**

**Likely Cause**: Subscription upgrade required (same as insider trading data)

**Next Steps**:
1. Contact QuiverQuant to confirm government contracts endpoint and tier
2. Evaluate subscription upgrade for bundled access (insiders + contracts)
3. Consider alternative: USASpending.gov API (free but more complex)
4. Unblock when data access is available

---

## Why

Government contract awards are material events that can significantly impact a company's revenue and stock price. Academic research shows positive cumulative abnormal returns (CAR) in the days following contract announcements, particularly for aerospace, defense, and technology companies. Unlike insider trades (45-day or 2-day lag), contract awards are disclosed immediately, providing a faster signal. However, the strategy requires fundamental data (company revenue) to assess materiality, adding complexity. This strategy provides event-driven alpha from government procurement patterns.

---

## What Changes

### New Capabilities
- **Contract data fetching** - Integrate with QuiverQuant government contracts API endpoint
- **Materiality assessment** - Filter contracts by significance (% of annual revenue)
- **Sector-specific strategies** - Different approaches for defense vs. technology vs. services
- **Time-based exits** - Automatic position closure after 5-10 days (capture announcement effect)
- **Contract tracking** - Monitor contract modifications and renewals (future enhancement)

### Technical Components
- **New model**: `GovernmentContract` with fields: contract_value, agency, award_date, ticker, contract_type
- **QuiverClient enhancement**: Add `fetch_government_contracts()` method
- **FetchGovernmentContractsJob**: Daily background job
- **GenerateContractsPortfolio command**: Event-driven strategy
- **FundamentalDataService**: Fetch company revenue for materiality calculations
- **Database**: New government_contracts table

### Breaking Changes
- None - independent new capability

---

## Impact

### Affected Specs
- `government-contracts` (NEW) - Complete specification for contracts strategy
- `data-fetching` (MODIFIED) - Adds government contract fetching capability
- `trading-strategies` (MODIFIED) - Adds contracts portfolio generation command

### Affected Code
- Database: 1 new table (government_contracts), ~10 columns
- Models: 1 new model in `packs/data_fetching/app/models/`
- Services: QuiverClient enhancement + FundamentalDataService (new)
- Commands: 1 new command in `packs/trading_strategies/app/commands/`
- Jobs: 1 new job in `packs/data_fetching/app/jobs/`
- Tests: ~70 new test cases

### Performance Impact
- API calls: Daily fetch from QuiverQuant + fundamental data API calls
- Database: New table, minimal impact
- Strategy execution: <3 seconds (simple materiality filter + position sizing)

### External Dependencies
- QuiverQuant API `/beta/bulk/govcontracts` endpoint (Tier 2?)
- **NEW**: Fundamental data source for company revenue
  - Option 1: Alpaca fundamental data (if available)
  - Option 2: External API (e.g., Financial Modeling Prep, Alpha Vantage)
  - Option 3: Manual mapping for top 100 contract recipients (MVP)
