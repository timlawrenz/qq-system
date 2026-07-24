# Technical Design Document: Senate EFD Extraction Pipeline

## 1. Objective
Replace the defunct `senatestockwatcher` community aggregator by building a native, robust data extraction pipeline that fetches, parses, and normalizes Periodic Transaction Reports (PTRs) directly from the official Senate Electronic Financial Disclosure (EFD) portal (`efdsearch.senate.gov`).

## 2. Architecture and Components
The extraction pipeline will be broken down into three distinct, testable Ruby classes to adhere to Single Responsibility Principle (SRP) and facilitate Test-Driven Development (TDD).

### A. `SenateEfd::SessionManager`
**Responsibility:** Negotiate the click-wrap "I Agree" gate and maintain a valid session.
*   **Action:** 
    1. `GET /search/home/` to extract the hidden `csrfmiddlewaretoken` from the DOM and initial `csrftoken` cookie.
    2. `POST /search/home/` with `prohibition_agreement=1` and the CSRF token.
    3. Capture the resulting `sessionid` cookie.
*   **Output:** A valid `Cookie` string and `X-CSRFToken` header to be injected into all subsequent HTTP requests.

### B. `SenateEfd::IndexFetcher`
**Responsibility:** Query the DataTables API to retrieve the master index of filed PTRs.
*   **Action:** `POST /search/report/data/` using the active session.
*   **Payload:** Filter `report_types` to `[11]` (Periodic Transaction Reports) and page through the results (`start=0`, `length=100`, etc.) based on `recordsTotal`.
*   **Output:** An array of metadata hashes: 
    `{ first_name:, last_name:, description:, url:, date_received: }`
    *(Note: The `url` will be extracted from the HTML anchor tag inside the DataTables array).*

### C. `SenateEfd::ReportParser`
**Responsibility:** Fetch a specific PTR HTML page and parse the exact stock transactions.
*   **Action:** `GET /search/view/ptr/{uuid}/` using the active session.
*   **Parsing:** Use `Nokogiri` to parse the resulting HTML table (`table.table-striped`).
*   **Output:** An array of individual trades normalized to your system's schema:
    `{ ticker:, company:, transaction_date:, transaction_type: (Purchase|Sale), trade_size_usd:, asset_type: }`

## 3. Data Flow and Aggregation
To prevent hitting WAF rate limits or IP bans (since we must crawl 90+ individual URLs per periodic sweep), the pipeline will implement a stateful watermark:

1. **Watermarking:** The system will store the latest known `date_received` or PTR `uuid` in the database (`quiver_trades` or a new `sync_state` table). 
2. **Delta Fetching:** The `IndexFetcher` will only request PTRs filed *after* the watermark.
3. **Throttled Crawling:** For new PTRs, the orchestrator will crawl the `ReportParser` URLs sequentially, utilizing a strict `sleep(2)` delay between requests.
4. **Normalization:** The extracted trades will be mapped exactly to the former QuiverQuant schema so downstream code (like `current_positions`) expects the same `[ { ticker:, trade_size_usd: ... } ]` format.

## 4. Edge Cases and Known Vulnerabilities

### A. Non-Standard / Paper Filings
Some older or specific filings are uploaded as **Scanned PDFs** rather than digital web forms. 
*   **Design Decision:** `ReportParser` will gracefully skip and log any PTR where the asset description contains "PDF Disclosed Filing". We will *not* implement OCR (Tesseract/AWS Textract) in V1.

### B. Missing or Blank Tickers
Senators occasionally type "--" or leave the ticker blank for private equity or municipal bonds.
*   **Design Decision:** Drop any trade where `normalize_ticker` returns nil or blank, as the system only trades publicly listed equities via Alpaca.

### C. Session Expiry and WAF Bans
The session cookie expires if idle. If the pipeline receives a `302 Found` redirecting back to `/search/home/` during an API call, `SessionManager` must intercept, re-authenticate, and retry the request automatically.

## 5. TDD Implementation Plan (Next Steps)

1. **Phase 1: Session and Indexing (Mocked)**
   * Write RSpec fixtures utilizing saved VCR cassettes of the DataTables API response.
   * Build `SenateEfd::SessionManager` and `SenateEfd::IndexFetcher`.
   * *Success criteria:* Tests pass extracting URLs without making live web calls.

2. **Phase 2: HTML Parsing**
   * Download a sample PTR HTML file locally.
   * Write `SenateEfd::ReportParser` using Nokogiri to iterate over the `<tbody>` rows, extracting the Transaction Date, Ticker, Type, and Amount.
   * *Success criteria:* The parser turns the raw HTML into the standard `Hash` format currently used in `HouseSenateDisclosuresClient`.

3. **Phase 3: Integration and Limits**
   * Integrate the classes into a top-level `SenateDisclosuresClient`.
   * Add Faraday middleware for rate-limiting.
   * *Success criteria:* A successful end-to-end dry run updating the local `log/development.log`.
