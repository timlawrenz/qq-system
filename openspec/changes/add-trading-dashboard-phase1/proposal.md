# Change: Trading Dashboard Phase 1 (Live Account Metrics)

**Change ID**: `add-trading-dashboard-phase1`  
**Type**: Feature Addition (UI + operational visibility)  
**Status**: In Progress  
**Priority**: High  
**Created**: 2025-12-30  
**Estimated Effort**: 8–12 hours  

## Why

The trading system currently has no first-party UI for monitoring live account health, performance, and risk metrics. Operators must rely on Rails console queries or the Alpaca dashboard, which slows detection of issues like drawdowns, concentration risk, or unexpectedly high cash exposure.

## What Changes

### User-facing
- Add a server-rendered dashboard page at **`GET /dashboard`**.
- Render the UI using **ERB** + **ViewComponents**.
- Present account state from the **local database only** (no Alpaca calls during request handling):
  - Total equity, cash vs invested, position count, top positions (from latest `performance_snapshots`).
  - Period returns (Today/WTD/MTD/YTD) based on stored snapshot history.
  - Risk indicators (largest position concentration, drawdown from peak, simple diversification score) from snapshot payload.
  - Positions table from stored snapshot payload.

### Architecture (required)
- **Business logic MUST live in a Packwerk pack** (new pack: `packs/trading_dashboard`).
- Business logic MUST be implemented using **GLCommand** (https://github.com/givelively/gl_command) rather than controller/service ad-hoc logic.
- Rails controller acts only as a thin HTTP adapter:
  - auth/authorization (if/when added)
  - calling a command
  - rendering/formatting

## Scope

### Included (Phase 1)
- Single HTML page at `/dashboard`.
- 30-second cached snapshot of metrics (rate-limit friendly).
- ViewComponents for reusable cards/sections.
- Graceful degraded rendering when required DB data is missing (empty state / stale snapshot warning).

### Excluded (Future)
- AuthN/AuthZ hardening (Phase 2)
- DB-backed historical dashboard (Phase 2)
- Interactive charting (Phase 2/3)

## Impact

### Affected Specs
- **NEW**: `trading-dashboard` (delta spec added under this change).

### Affected Code (planned)
- **New pack**: `packs/trading_dashboard/`
  - `app/commands/` – GLCommand entrypoints to build dashboard snapshot
  - `app/services/` – small helpers only (formatting/calculators), used by commands
- UI shell (non-domain):
  - `app/controllers/trading_dashboard_controller.rb`
  - `app/views/trading_dashboard/index.html.erb`
  - `app/components/trading_dashboard/*` (ViewComponents)
- Uses existing packs for data access:
  - `packs/performance_reporting` (`PerformanceSnapshot`) for stored account snapshots
  - `packs/trades` (`AlpacaOrder`) optionally for recent trade counts/last activity

### Breaking Changes
- If the app is currently API-only (`config.api_only = true`), this change will flip it to HTML-capable Rails (still can remain API-first). This is behaviorally significant but not an API break.

## Technical Design

### High-level flow

```
Browser
  GET /dashboard
    ↓
TradingDashboardController#index (thin)
  ↓ calls
TradingDashboard::FetchTradingDashboardSnapshot (GLCommand)
  ↓ queries
PerformanceSnapshot / AlpacaOrder (local DB)
  ↓ returns
Structured metrics hash
  ↓ renders
ERB template + ViewComponents
```

### Pack boundary
- `packs/trading_dashboard` owns:
  - translating DB snapshots into a dashboard view-model
  - lightweight derived metrics based on stored snapshots (e.g. Today/WTD/MTD/YTD based on snapshot series)
  - caching strategy for request-time rendering
  - error normalization into user-displayable state
- `app/controllers` / `app/views` owns:
  - request/response orchestration
  - presentation layout
  - ViewComponents

### GLCommand usage
Commands SHOULD be small and chainable. Proposed command surface:
- `FetchTradingDashboardSnapshot` (orchestrator; caches)
  - `FetchAccountState`
  - `FetchPositions`
  - `FetchEquityHistory`
  - `CalculatePeriodReturns`
  - `CalculateRiskMetrics`

Controller usage pattern:

```ruby
result = TradingDashboard::FetchTradingDashboardSnapshot.call

if result.success?
  @metrics = result.metrics
else
  @error = result.error_message
end
```

### Caching
- Cache key: `trading_dashboard:snapshot:v1`
- TTL: 30 seconds
- Cache inside the orchestrator command so repeated page refreshes do not hammer the DB.
- Alpaca calls (if any) happen out-of-band via the performance reporting pipeline, not in the dashboard request.

### UI (ERB + ViewComponents)
- `TradingDashboard::MetricCardComponent`
- `TradingDashboard::AllocationComponent`
- `TradingDashboard::PerformanceGridComponent`
- `TradingDashboard::RiskSummaryComponent`
- `TradingDashboard::PositionsTableComponent`

## Testing Strategy (planned)
- Unit tests for commands in `packs/trading_dashboard` (mock `AlpacaService`).
- ViewComponent specs for formatting and conditional styling.
- Request spec for `/dashboard` verifying:
  - success path renders
  - failure path shows error banner

## Validation
- `bundle exec rspec`
- `bundle exec rubocop`
- `bundle exec packwerk check`
- Manual: `curl -s http://localhost:3000/dashboard` (after enabling HTML rendering)
