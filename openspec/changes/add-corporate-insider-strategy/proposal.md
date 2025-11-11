# Change Proposal: Corporate Insider Trading Strategy

**Change ID**: `add-corporate-insider-strategy`  
**Type**: Feature Addition  
**Status**: ⏸️ BLOCKED - Subscription Required  
**Priority**: High (Priority 2 in roadmap)  
**Estimated Effort**: 3-4 weeks  
**Created**: 2025-11-10  
**Blocked Date**: 2025-11-11  
**Blocker**: QuiverQuant subscription tier does not include insider trading data  

---

## ⚠️ Current Blocker (Nov 11, 2025)

**API Endpoint Confirmed**: `https://api.quiverquant.com/beta/live/insiders`  
**Response**: `{"detail": "Upgrade your subscription plan to access this dataset."}`

**Next Steps**:
1. Monitor Enhanced Congressional Strategy performance (1-2 weeks)
2. Evaluate ROI of QuiverQuant subscription upgrade
3. Consider alternative data sources (SEC EDGAR, Financial Modeling Prep)
4. Unblock when data access is available

---

## Why

The current system only implements congressional trading (Strategy 1.1), covering only one half of the "Mimicking Political and Corporate Insiders" strategy from the strategic framework. Corporate insider trades (directors, CEOs, CFOs buying/selling their own company stock) are a proven alpha source with statistically significant positive abnormal returns. Adding this completes Strategy #1 and provides signal diversification through a complementary data source with faster disclosure (2 business days vs 45 days for congressional trades).

---

## What Changes

### New Capabilities
- **Corporate insider data fetching** - Integrate with QuiverQuant insider trading API endpoint
- **Insider trade processing** - Parse and persist insider transactions with relationship types (CEO, CFO, Director)
- **Insider mimicry strategy** - Long on insider purchases, optional short on sales
- **Transaction filtering** - Exclude scheduled/automatic trades (Form 4 vs Form 144)
- **Position sizing by role** - Weight C-suite trades higher than general directors

### Technical Components
- **QuiverClient enhancement** - Add `fetch_insider_trades()` method
- **QuiverTrade model extension** - Add fields: relationship, shares_held, percent_of_holdings, trade_type
- **New strategy command** - `GenerateInsiderMimicryPortfolio` 
- **Background job** - `FetchInsiderTradesJob` (runs daily)
- **Database migration** - 3 new columns on quiver_trades table

### Breaking Changes
- None - reuses existing QuiverTrade model with new trader_source value ('insider')

---

## Impact

### Affected Specs
- `insider-trading` (NEW) - Complete specification for insider mimicry strategy
- `data-fetching` (MODIFIED) - Adds insider trade fetching capability
- `trading-strategies` (MODIFIED) - Adds insider portfolio generation command

### Affected Code
- Database: 1 migration adding 3 columns to quiver_trades
- Models: Enhance existing QuiverTrade with new scopes and validations
- Services: Enhance QuiverClient with insider trading endpoint
- Commands: 1 new command in `packs/trading_strategies/app/commands/`
- Jobs: 1 new job in `packs/data_fetching/app/jobs/`
- Tests: ~60 new test cases

### Performance Impact
- API calls: Daily fetch from QuiverQuant insider trading endpoint
- Database: Reuses existing quiver_trades table (no performance degradation)
- Strategy execution: <3 seconds (similar to congressional strategy)

### External Dependencies
- QuiverQuant API `/beta/bulk/insidertrading` endpoint (requires Tier 2 subscription?)
- 2-business-day disclosure lag (faster than congressional trades)
