# Government Contracts Strategy

**Status:** Paper-ready (quarterly totals)

## Data Source
Quiver govcontracts endpoints provide **quarterly totals** (not award-level events):
- `GET /beta/live/govcontracts` → last quarter totals for all tickers
- `GET /beta/historical/govcontracts/{ticker}` → quarterly history for one ticker

The system ingests these into `GovernmentContract` rows with:
- `contract_type = QuarterlyTotal`
- `award_date = quarter end date` (e.g., Q4 2025 → 2025-12-31)
- `contract_id = govcontracts:{TICKER}:{YEAR}:Q{QTR}`

## Fundamentals / Sector Classification
We use Financial Modeling Prep (FMP) to cache company profile data per ticker:
- `sector`
- `industry`
- (optional) `annual_revenue` if available

Env var: `FMP_API_KEY`

## How Paper Trading Uses It
In `config/portfolio_strategies.yml` (paper), the strategy is enabled with weight 10%.

**Note:** Because Quiver provides quarterly totals, this behaves like a **quarterly factor / exposure** signal.
If we get award-level contract events later, we can switch to a true post-award event-driven holding-period strategy.
