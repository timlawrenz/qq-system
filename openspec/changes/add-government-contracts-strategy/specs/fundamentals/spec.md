## ADDED Requirements

### Requirement: Company Profile Data Source (FMP)
The system SHALL integrate a fundamentals/company-profile data source that returns `sector` and `industry` for a given ticker symbol.

#### Scenario: Fetch a company profile
- **WHEN** FmpClient.fetch_company_profile('LMT') is executed
- **THEN** the client calls the FMP company profile endpoint
- **AND** returns a normalized hash containing sector and industry

#### Scenario: Parse sector/industry fields
- **WHEN** FMP returns a profile payload
- **THEN** the system extracts `sector` and `industry`
- **AND** stores them in a cached CompanyProfile record

#### Scenario: Cache profile records
- **WHEN** a ticker has a cached CompanyProfile updated within TTL (>= 30 days)
- **THEN** FundamentalDataService returns cached values
- **AND** does not call FMP

#### Scenario: Respect Basic plan quota
- **WHEN** the system encounters many tickers in a day
- **THEN** it should only call FMP for unknown/un-cached tickers
- **AND** enforce a configurable per-day ceiling (default 200) as a safety buffer under 250/day
- **AND** never persist or log the API key

#### Scenario: Handle errors
- **WHEN** FMP returns 401/403
- **THEN** raise a clear authentication/permission error
- **WHEN** FMP returns 429
- **THEN** surface a rate limit error and rely on cached data

---

### Requirement: Sector Classification for Contracts
The system SHALL classify contractors into coarse sectors using cached company profile data.

#### Scenario: Classify sector
- **WHEN** SectorClassifier.sector_for('LMT') is called
- **THEN** it uses FundamentalDataService.get_sector('LMT')
- **AND** maps it into a coarse bucket (e.g., defense/technology/services)

#### Scenario: Unknown sector fallback
- **WHEN** sector is missing
- **THEN** classify as "services" (default)
- **AND** log a warning for later review
