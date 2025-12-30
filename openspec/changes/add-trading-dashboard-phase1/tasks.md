# Implementation Tasks: Trading Dashboard Phase 1

## 1. Pack + Command Architecture
- [x] 1.1 Create new pack `packs/trading_dashboard/` (package.yml, standard folders)
- [x] 1.2 Define dependencies in `packs/trading_dashboard/package.yml`
  - [x] depend on `packs/performance_reporting` (for `PerformanceSnapshot`)
  - [ ] depend on `packs/trades` (for `AlpacaOrder`, optional)
- [x] 1.3 Implement GLCommand orchestrator: `FetchTradingDashboardSnapshot`
  - [x] returns `metrics:` hash on success
  - [x] normalizes failures into a user-safe error message
  - [x] performs `Rails.cache.fetch` with TTL=30s
- [x] 1.4 Implement sub-commands / command chain for DB-only dashboard data:
  - [x] load latest performance snapshot (and detect staleness)
  - [x] load snapshot series for period returns (today/wtd/mtd/ytd)
  - [x] positions list from snapshot payload
  - [x] risk metrics from snapshot payload

## 2. Rails UI Shell (ERB)
- [x] 2.1 Enable HTML rendering if currently API-only (review `config/application.rb`)
- [x] 2.2 Add route: `get "/dashboard" => "trading_dashboard#index"`
- [x] 2.3 Add `TradingDashboardController#index`
  - [x] calls `FetchTradingDashboardSnapshot`
  - [x] renders `index.html.erb`
  - [x] handles error banner on command failure
- [x] 2.4 Create ERB template `app/views/trading_dashboard/index.html.erb`

## 3. ViewComponents
- [x] 3.1 Create components under `app/components/trading_dashboard/`
- [x] 3.2 Ensure components accept plain data inputs (no service calls)
- [ ] 3.3 Implement dark theme styling (Tailwind v4)

## 4. Testing
- [x] 4.1 Command specs (mock AlpacaService)
- [ ] 4.2 ViewComponent specs (render_inline)
- [x] 4.3 Request spec for `/dashboard`

## 5. Quality Gates
- [ ] 5.1 `bundle exec rspec`
- [x] 5.2 `bundle exec rubocop`
- [ ] 5.3 `bundle exec packwerk check`
