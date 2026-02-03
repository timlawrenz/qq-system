## ADDED Requirements

### Requirement: Trading dashboard endpoint
The system SHALL provide an HTML dashboard page at `GET /dashboard`.

#### Scenario: Render dashboard successfully
- **WHEN** a user requests `GET /dashboard`
- **AND** Alpaca data can be retrieved
- **THEN** the system renders an HTML page with live account metrics

#### Scenario: Render dashboard with missing DB data
- **WHEN** a user requests `GET /dashboard`
- **AND** there is no suitable stored snapshot data in the local database
- **THEN** the system renders an HTML page containing a user-friendly empty state
- **AND** the system logs diagnostic details

---

### Requirement: Business logic isolation via Packwerk + GLCommand
Dashboard data aggregation and metric calculation SHALL be implemented as GLCommands inside a dedicated Packwerk pack.

#### Scenario: Controller remains thin
- **WHEN** `GET /dashboard` is executed
- **THEN** the controller only orchestrates the request and calls a single command entrypoint
- **AND** metric calculation logic is not implemented in the controller

---

### Requirement: Cached snapshot for request-time rendering
The system SHALL cache dashboard metrics for 30 seconds to avoid unnecessary repeated DB queries during rapid refresh.

#### Scenario: Two requests within TTL
- **WHEN** `GET /dashboard` is called twice within 30 seconds
- **THEN** the second request uses cached metrics
- **AND** does not re-query the database for dashboard metrics

---

### Requirement: Account health overview (DB-only)
The system SHALL display key account health indicators from the local database: total equity, cash vs invested allocation, position count, and top positions by market value.

#### Scenario: Display account summary
- **WHEN** the dashboard renders
- **THEN** it shows total equity prominently
- **AND** it shows cash and invested amounts and percentages
- **AND** it shows the top 5 positions by market value

---

### Requirement: Performance metrics (DB-only)
The system SHALL display period returns: Today, WTD, MTD, and YTD based on stored snapshot history.

#### Scenario: Calculate YTD return
- **WHEN** equity history includes a point at the beginning of the year and a current point
- **THEN** the dashboard shows YTD $ and % change based on those values

---

### Requirement: Risk metrics (DB-only)
The system SHALL display risk indicators including concentration (largest position %), drawdown from peak equity, and a simple diversification score from stored snapshot payload.

#### Scenario: Concentration warning
- **WHEN** the largest position exceeds 20% of portfolio market value
- **THEN** the dashboard highlights a concentration warning state

---

### Requirement: No Alpaca API calls during dashboard requests
The dashboard request handler SHALL NOT call AlpacaService; it SHALL use only locally persisted data.

#### Scenario: Request does not hit Alpaca
- **WHEN** `GET /dashboard` is served
- **THEN** the request handler does not instantiate or call AlpacaService

---

### Requirement: ERB + ViewComponents UI composition
The dashboard SHALL be rendered with an ERB template composed of ViewComponents.

#### Scenario: Render via components
- **WHEN** the dashboard renders
- **THEN** repeated UI patterns (cards, grids, tables) are produced via ViewComponents
