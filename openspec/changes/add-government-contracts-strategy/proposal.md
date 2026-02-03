# Change Proposal: Government Contracts Strategy

**Change ID**: `add-government-contracts-strategy`  
**Type**: Feature Addition  
**Status**: 🟡 IN PROGRESS (Fundamentals integration pending)  
**Priority**: Medium (Backlog - Priority 5 in roadmap)  
**Estimated Effort**: 3-4 weeks  
**Created**: 2025-11-10  
**Previously Blocked Date**: 2025-11-11  
**Previous Blocker**: QuiverQuant subscription tier did not include government contracts data  

**Update (Dec 2025)**: Government contracts access confirmed via QuiverQuant Trader tier; implementation unblocked.

---

## Status Update (Dec 2025)

Government contracts API access is now available under the QuiverQuant Trader tier.

**Confirmed Endpoint Pattern**:
- `/beta/historical/govcontracts/{ticker}` (ticker-specific historical)

**Implementation Note**:
- The system should support both ticker-specific historical fetching and (if enabled by Quiver) bulk fetching.
- The primary requirement is: *fetch contracts for the symbols we care about*.

---

## Current Blocker (Jan 2026)

**Blocker**: We still need a reliable fundamentals/profile data source to classify `sector/industry` (and ideally revenue) for materiality filtering.

**Plan**: Use Financial Modeling Prep (FMP) company profile endpoint for cached `sector` + `industry` and optional `revenue`.

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
- **NEW model**: `CompanyProfile` (or `CompanyFundamental`) cached per ticker (sector, industry, revenue, updated_at)
- **NEW client**: `FmpClient` to fetch company profile/fundamentals from FMP
- **FundamentalDataService**: Read-through cache that uses the DB first, then FMP, then fallback
- **Database**: New government_contracts table + company_profiles/fundamentals table

### Breaking Changes
- None - independent new capability

---

## Impact

### Affected Specs
- `government-contracts` (NEW) - Complete specification for contracts strategy
- `fundamentals` (NEW) - Company profile cache + sector/industry classification via FMP
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
- QuiverQuant government contracts endpoint (ticker-specific historical confirmed)
- **NEW**: Financial Modeling Prep (FMP) company profile endpoint (Basic/free plan)
  - Used for: `sector`, `industry`, (optional) `revenue`
  - Expectation: aggressive caching → minimal daily calls
  - Credential: `FMP_API_KEY`
