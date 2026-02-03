# Change Proposal: Corporate Lobbying Data Integration

**Change ID**: `add-lobbying-data`  
**Type**: Feature Addition  
**Status**: Draft  
**Priority**: High  
**Estimated Effort**: 2-3 weeks  
**Created**: 2025-12-10  
**Depends On**: None (Tier 2 API access confirmed)

---

## Problem Statement

The trading system currently only uses congressional trading data (Tier 1) for signal generation. The Trader tier upgrade provides access to corporate lobbying data (Tier 2), which academic research shows generates **5.5-6.7% annual excess returns** through a lobbying intensity factor.

**Current State:**
- ❌ No lobbying data in database
- ❌ No QuiverClient method to fetch lobbying data
- ❌ No lobbying-based trading strategy
- ✅ Trader tier API access confirmed (tested Dec 10, 2025)

**Gap:**
- Missing a proven, uncorrelated alpha source
- Single-strategy platform (congressional only)
- No long-term factor strategies (all event-driven)

**Opportunity:**
- Academic backing: $200 market value per $1 lobbying spend
- Multi-year persistence (not subject to rapid alpha decay)
- Quarterly rebalancing (low turnover)
- Rich dataset: 1,565+ records for GOOGL alone

---

## Proposed Solution

Build end-to-end lobbying data integration and factor strategy:

1. **Data Fetching** - Extend QuiverClient to fetch lobbying disclosures
2. **Data Storage** - New LobbyingExpenditure model with quarterly aggregation
3. **Factor Strategy** - Lobbying intensity long/short portfolio
4. **Background Jobs** - Automated quarterly data refresh

This enables a **long-term factor strategy** that complements the existing event-driven congressional strategy.

---

## Requirements

### Functional Requirements

**FR-1**: Fetch lobbying data from QuiverQuant API
- Endpoint: `/beta/historical/lobbying/{ticker}` (ticker-specific, not bulk)
- Support ticker list input (iterate over multiple tickers)
- Parse fields: Date, Quarter, Amount, Client, Issues
- Handle rate limiting (1000 calls/day limit)
- Return structured data array

**FR-2**: Persist lobbying data to database
- New table: `lobbying_expenditures`
- Fields: ticker, quarter, amount, client, issues, reported_at
- Composite unique index: (ticker, quarter, client)
- Idempotent upserts (find_or_create_by)
- Quarterly aggregation by ticker

**FR-3**: Calculate lobbying intensity metric
- Formula: `lobbying_intensity = total_spend / market_cap`
- Requires market cap data (Alpaca API or external source)
- Normalize to z-scores across universe
- Rank stocks by intensity

**FR-4**: Generate lobbying factor portfolio
- Long top quintile (highest lobbying intensity)
- Short bottom quintile (lowest/no lobbying)
- Market-neutral target (50% long, 50% short)
- Equal-weight within quintiles
- Quarterly rebalancing

**FR-5**: Background job for data refresh
- `FetchLobbyingDataJob` - fetches for ticker list
- Run quarterly (Jan, Apr, Jul, Oct)
- Process 45 days after quarter end (disclosure deadline)
- Batch ticker processing with rate limit management

### Non-Functional Requirements

**NFR-1**: Performance
- Handle 100+ tickers per batch
- Respect 1000 calls/day rate limit
- Complete quarterly refresh within 1 hour

**NFR-2**: Reliability
- Idempotent data fetching (safe to retry)
- Handle partial failures (continue on error)
- Structured logging for monitoring

**NFR-3**: Data Quality
- Validate quarterly aggregation logic
- Handle missing/sparse data (not all companies lobby)
- Filter out non-public companies

---

## Technical Design

### Components

**Location**: `packs/data_fetching/`

```
packs/data_fetching/
├── app/
│   ├── commands/
│   │   └── fetch_lobbying_data.rb       # New
│   ├── jobs/
│   │   └── fetch_lobbying_data_job.rb   # New
│   ├── models/
│   │   └── lobbying_expenditure.rb      # New
│   └── services/
│       └── quiver_client.rb             # Extend existing
```

**Location**: `packs/trading_strategies/`

```
packs/trading_strategies/
├── app/
│   ├── commands/
│   │   └── trading_strategies/
│   │       └── generate_lobbying_factor_portfolio.rb  # New
│   └── services/
│       └── lobbying_intensity_calculator.rb           # New
```

---

## Implementation Plan

### Phase 1: Data Integration (Week 1)

**1.1 Database Schema**
```ruby
# db/migrate/YYYYMMDDHHMMSS_create_lobbying_expenditures.rb
class CreateLobbyingExpenditures < ActiveRecord::Migration[8.0]
  def change
    create_table :lobbying_expenditures do |t|
      t.string :ticker, null: false
      t.string :quarter, null: false        # "Q1 2025"
      t.decimal :amount, precision: 15, scale: 2
      t.string :client
      t.text :issues
      t.date :reported_at
      
      t.timestamps
      
      t.index [:ticker, :quarter, :client], unique: true, name: 'idx_lobbying_unique'
      t.index [:ticker, :quarter]
      t.index :reported_at
    end
  end
end
```

**1.2 Model**
```ruby
# packs/data_fetching/app/models/lobbying_expenditure.rb
class LobbyingExpenditure < ApplicationRecord
  validates :ticker, :quarter, :amount, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  
  scope :for_quarter, ->(quarter) { where(quarter: quarter) }
  scope :for_ticker, ->(ticker) { where(ticker: ticker) }
  
  # Aggregate total spend by ticker and quarter
  def self.quarterly_totals(quarter)
    where(quarter: quarter)
      .group(:ticker)
      .sum(:amount)
  end
end
```

**1.3 Extend QuiverClient**
```ruby
# packs/data_fetching/app/services/quiver_client.rb
class QuiverClient
  # Existing methods...
  
  def fetch_lobbying_data(ticker)
    rate_limit
    
    path = "/beta/historical/lobbying/#{ticker}"
    
    Rails.logger.info("Fetching lobbying data for #{ticker}")
    
    begin
      response = @connection.get(path)
      handle_lobbying_response(response, ticker)
    rescue Faraday::Error => e
      handle_api_error(e)
    end
  end
  
  private
  
  def handle_lobbying_response(response, ticker)
    case response.status
    when 200
      parse_lobbying_data(response.body, ticker)
    when 404
      Rails.logger.info("No lobbying data found for #{ticker}")
      []
    when 403
      raise StandardError, 'Quiver API access forbidden. Check Tier 2 access.'
    else
      raise StandardError, "Quiver API error (#{response.status})"
    end
  end
  
  def parse_lobbying_data(body, ticker)
    data = JSON.parse(body)
    return [] unless data.is_a?(Array)
    
    data.map do |record|
      {
        ticker: ticker,
        quarter: record['Quarter'] || extract_quarter_from_date(record['Date']),
        amount: parse_amount(record['Amount']),
        client: record['Client'],
        issues: record['Issue'],
        reported_at: parse_date(record['Date'])
      }
    end
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse lobbying data: #{e.message}")
    []
  end
  
  def extract_quarter_from_date(date_string)
    return nil if date_string.blank?
    
    date = Date.parse(date_string)
    quarter = (date.month - 1) / 3 + 1
    "Q#{quarter} #{date.year}"
  rescue ArgumentError
    nil
  end
  
  def parse_amount(amount_string)
    return nil if amount_string.blank?
    
    amount_string.to_s.gsub(/[,$]/, '').to_f
  end
end
```

---

### Phase 2: Data Fetching Command (Week 1)

**2.1 FetchLobbyingData Command**
```ruby
# packs/data_fetching/app/commands/fetch_lobbying_data.rb
class FetchLobbyingData < GLCommand
  needs :tickers, array_of: String
  
  def call
    results = {
      total: 0,
      new: 0,
      updated: 0,
      errors: 0,
      tickers_processed: 0,
      failed_tickers: []
    }
    
    client = QuiverClient.new
    
    tickers.each do |ticker|
      begin
        lobbying_records = client.fetch_lobbying_data(ticker)
        
        lobbying_records.each do |record_data|
          lobbying = LobbyingExpenditure.find_or_initialize_by(
            ticker: record_data[:ticker],
            quarter: record_data[:quarter],
            client: record_data[:client]
          )
          
          is_new = lobbying.new_record?
          
          lobbying.assign_attributes(
            amount: record_data[:amount],
            issues: record_data[:issues],
            reported_at: record_data[:reported_at]
          )
          
          if lobbying.save
            results[:total] += 1
            is_new ? results[:new] += 1 : results[:updated] += 1
          else
            results[:errors] += 1
            Rails.logger.error("Failed to save lobbying record: #{lobbying.errors.full_messages}")
          end
        end
        
        results[:tickers_processed] += 1
        
      rescue => e
        results[:errors] += 1
        results[:failed_tickers] << ticker
        Rails.logger.error("Failed to fetch lobbying data for #{ticker}: #{e.message}")
      end
    end
    
    Rails.logger.info("Lobbying data fetch complete: #{results}")
    results
  end
end
```

**2.2 Background Job**
```ruby
# packs/data_fetching/app/jobs/fetch_lobbying_data_job.rb
class FetchLobbyingDataJob < ApplicationJob
  queue_as :default
  
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(tickers: nil)
    tickers ||= default_ticker_universe
    
    Rails.logger.info("Starting lobbying data fetch for #{tickers.length} tickers")
    
    result = FetchLobbyingData.call(tickers: tickers)
    
    if result[:errors] > 0
      Rails.logger.warn("Lobbying fetch completed with errors: #{result}")
    else
      Rails.logger.info("Lobbying fetch SUCCESS: #{result}")
    end
    
    result
  end
  
  private
  
  def default_ticker_universe
    # S&P 500 or custom universe
    # For now, use top lobbying companies
    %w[
      GOOGL AAPL MSFT AMZN META FB
      JNJ PFE MRK ABT BMY
      JPM BAC GS MS WFC
      CVX XOM BP
      BA LMT RTX NOC GD
    ]
  end
end
```

---

### Phase 3: Lobbying Intensity Calculator (Week 2)

**3.1 Intensity Calculator Service**
```ruby
# packs/trading_strategies/app/services/lobbying_intensity_calculator.rb
class LobbyingIntensityCalculator
  def initialize(quarter:)
    @quarter = quarter
  end
  
  def calculate_intensities
    # Get quarterly lobbying totals
    lobbying_totals = LobbyingExpenditure.quarterly_totals(@quarter)
    
    # Get market caps (from Alpaca or cache)
    market_caps = fetch_market_caps(lobbying_totals.keys)
    
    # Calculate intensity for each ticker
    intensities = {}
    
    lobbying_totals.each do |ticker, total_spend|
      market_cap = market_caps[ticker]
      
      next if market_cap.nil? || market_cap <= 0
      
      # Lobbying intensity = total spend / market cap
      intensity = (total_spend / market_cap) * 1_000_000 # Basis points
      
      intensities[ticker] = {
        lobbying_spend: total_spend,
        market_cap: market_cap,
        intensity: intensity
      }
    end
    
    # Normalize to z-scores
    normalize_intensities(intensities)
  end
  
  private
  
  def fetch_market_caps(tickers)
    # Use Alpaca API to get current market caps
    # TODO: Implement market cap fetching
    # For now, return stub data
    tickers.to_h { |t| [t, 100_000_000_000] } # $100B stub
  end
  
  def normalize_intensities(intensities)
    values = intensities.values.map { |v| v[:intensity] }
    mean = values.sum / values.size
    std_dev = Math.sqrt(values.sum { |v| (v - mean)**2 } / values.size)
    
    intensities.each do |ticker, data|
      z_score = (data[:intensity] - mean) / std_dev
      intensities[ticker][:z_score] = z_score
    end
    
    intensities
  end
end
```

---

### Phase 4: Lobbying Factor Strategy (Week 2-3)

**4.1 Generate Portfolio Command**
```ruby
# packs/trading_strategies/app/commands/trading_strategies/generate_lobbying_factor_portfolio.rb
module TradingStrategies
  class GenerateLobbyingFactorPortfolio < GLCommand
    needs :quarter, default: -> { current_quarter }
    needs :long_pct, default: 0.5  # 50% long
    needs :short_pct, default: 0.5 # 50% short
    
    def call
      # Calculate lobbying intensities
      calculator = LobbyingIntensityCalculator.new(quarter: quarter)
      intensities = calculator.calculate_intensities
      
      # Rank by z-score
      ranked = intensities.sort_by { |_ticker, data| -data[:z_score] }
      
      # Determine quintiles
      quintile_size = (ranked.size / 5.0).ceil
      
      long_tickers = ranked.take(quintile_size).map(&:first)
      short_tickers = ranked.last(quintile_size).map(&:first)
      
      # Get current equity
      account = AlpacaService.new.get_account
      total_equity = account['equity'].to_f
      
      # Calculate position sizes
      long_allocation = total_equity * long_pct
      short_allocation = total_equity * short_pct
      
      long_weight = long_tickers.any? ? long_allocation / long_tickers.size : 0
      short_weight = short_tickers.any? ? -short_allocation / short_tickers.size : 0
      
      # Build target positions
      positions = []
      
      long_tickers.each do |ticker|
        positions << {
          ticker: ticker,
          weight: long_weight,
          reason: "Long: Top quintile lobbying intensity (z=#{intensities[ticker][:z_score].round(2)})"
        }
      end
      
      short_tickers.each do |ticker|
        positions << {
          ticker: ticker,
          weight: short_weight,
          reason: "Short: Bottom quintile lobbying intensity (z=#{intensities[ticker][:z_score].round(2)})"
        }
      end
      
      Rails.logger.info("Generated lobbying factor portfolio: #{positions.size} positions")
      
      {
        positions: positions,
        long_count: long_tickers.size,
        short_count: short_tickers.size,
        total_long: long_allocation,
        total_short: short_allocation
      }
    end
    
    private
    
    def current_quarter
      date = Date.today
      quarter = (date.month - 1) / 3 + 1
      "Q#{quarter} #{date.year}"
    end
  end
end
```

---

## Testing Strategy

### Unit Tests

**Test QuiverClient#fetch_lobbying_data**:
- VCR cassette with real API response
- Parse fields correctly
- Handle 404 gracefully
- Extract quarter from date

**Test LobbyingExpenditure model**:
- Validations (ticker, quarter, amount)
- Uniqueness constraint
- Quarterly aggregation

**Test FetchLobbyingData command**:
- Fetch and persist records
- Idempotent upserts
- Error handling per ticker

**Test LobbyingIntensityCalculator**:
- Calculate intensity correctly
- Normalize to z-scores
- Handle missing market caps

**Test GenerateLobbyingFactorPortfolio**:
- Rank by intensity
- Quintile allocation
- Long/short positions
- Market-neutral balance

### Integration Tests

**End-to-End Data Flow**:
1. Fetch lobbying data (mock API)
2. Persist to database
3. Calculate intensities
4. Generate portfolio
5. Verify positions

---

## Risk Assessment

### Technical Risks

**R-1: Rate Limiting** (Medium)
- 1000 calls/day limit
- Need to batch ticker processing
- **Mitigation**: Process 25 tickers/day, complete universe in 4 days

**R-2: Market Cap Data** (High)
- Need market cap for intensity calculation
- Alpaca may not provide market cap directly
- **Mitigation**: Use Alpaca fundamental data or external API

**R-3: Data Sparsity** (Low)
- Not all companies lobby
- May have small sample size
- **Mitigation**: Filter to known lobbying universe

### Business Risks

**R-4: Strategy Performance** (Medium)
- Academic results may not translate to live trading
- Factor may be crowded
- **Mitigation**: Paper trade for 1 quarter before live

---

## Success Metrics

### Data Integration Success
- ✅ 100+ tickers with lobbying data
- ✅ Quarterly data spanning 2+ years
- ✅ < 5% error rate on fetches

### Strategy Success
- ✅ Portfolio construction completes without errors
- ✅ Market-neutral (±5% long/short balance)
- ✅ 20-30 positions (diversification)
- ✅ Quarterly rebalancing executes successfully

### Performance Targets (After 1 Year)
- Target: 5.5% annual excess return (academic baseline)
- Acceptable: 3% excess return
- Sharpe Ratio: > 1.0

---

## Rollout Plan

### Week 1: Data Integration
- Day 1-2: Database schema and model
- Day 3-4: Extend QuiverClient
- Day 5: FetchLobbyingData command and job

### Week 2: Strategy Development
- Day 1-2: LobbyingIntensityCalculator
- Day 3: Market cap data integration
- Day 4-5: GenerateLobbyingFactorPortfolio

### Week 3: Testing & Validation
- Day 1-2: Unit tests
- Day 3: Integration tests
- Day 4: Manual testing with real data
- Day 5: Paper trading setup

### Week 4+: Paper Trading
- Run strategy in paper account for Q1 2026
- Monitor performance vs. benchmark
- Collect data for validation

---

## Open Questions

1. **Market Cap Data Source**: Use Alpaca fundamental data, or external API (e.g., Financial Modeling Prep)?
2. **Ticker Universe**: S&P 500, Russell 3000, or custom lobbying-focused list?
3. **Rebalancing Frequency**: Quarterly (recommended) or monthly?
4. **Shorting Capability**: Does Alpaca paper account support shorting? Need to verify.
5. **Performance Benchmark**: S&P 500, market-neutral hedge fund index, or custom?

---

## Dependencies

### Internal
- ✅ QuiverClient service exists
- ✅ AlpacaService exists
- ✅ GLCommand infrastructure exists
- ✅ SolidQueue for background jobs

### External
- ✅ Quiver API Tier 2 access (confirmed)
- ⚠️  Market cap data source (TBD)
- ⚠️  Alpaca shorting capability (TBD)

---

## References

### Academic Literature
- **"Corporate Lobbying and Firm Performance"** (Igan & Mishra, 2011)
  - Finding: 5.5-6.7% excess annual return
  - Top quintile lobbying intensity outperforms

- **"Determinants and Effects of Corporate Lobbying"** (Chen et al., 2015)
  - Finding: $200 market value per $1 lobbying spend
  - Multi-year persistence

### API Documentation
- **Quiver API**: https://api.quiverquant.com/docs/
- **Test Results**: `docs/operations/API_ACCESS_TEST_RESULTS.md`
- **Endpoint**: `/beta/historical/lobbying/{ticker}`

### Internal Documentation
- **Trader Upgrade**: `docs/operations/QUIVER_TRADER_UPGRADE.md`
- **Strategy Roadmap**: `docs/strategy/STRATEGY_ROADMAP.md`
- **Strategic Framework**: `docs/strategy/strategic-framework-with-alternative-data.md`

---

**Status**: Draft  
**Next**: Review and approve proposal  
**Approved By**: [Pending]  
**Approval Date**: [Pending]
