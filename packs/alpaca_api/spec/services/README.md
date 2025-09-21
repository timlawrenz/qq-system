# AlpacaService VCR Tests

This directory contains VCR (Video Cassette Recorder) tests for the `AlpacaService` class, which test the service's interaction with the Alpaca Trading API.

## Overview

The VCR tests validate:
- `account_equity` method - fetching account equity from Alpaca API
- `current_positions` method - retrieving current stock positions
- `place_order` method - placing buy/sell orders with various parameters
- Integration scenarios combining multiple API calls

## Test Structure

### Account Equity Tests
- ✅ Successful API response with valid equity data
- ✅ Proper BigDecimal formatting and precision
- ✅ Authentication error handling
- ✅ API unavailability error handling

### Current Positions Tests  
- ✅ Successful positions retrieval with proper data structure
- ✅ Empty positions handling
- ✅ Position data validation (symbols, quantities, market values)
- ✅ Authentication and API error handling

### Place Order Tests
- ✅ Buy orders with notional amounts
- ✅ Sell orders with quantities
- ✅ Fractional share orders
- ✅ Authentication errors
- ✅ Insufficient funds errors
- ✅ Market closed errors
- ✅ Invalid symbol errors
- ✅ Parameter validation (before API calls)

### Integration Scenarios
- ✅ Multiple API calls in sequence
- ✅ Complete trading workflow simulation

## Running the Tests

### Prerequisites
To record new cassettes with real API interactions, you need:
- Valid Alpaca API credentials (API key and secret)
- Set environment variables: `ALPACA_API_KEY` and `ALPACA_SECRET_KEY`
- Or configure them in Rails credentials under `:alpaca` section

### Running Tests

```bash
# Run all VCR tests for AlpacaService
bundle exec rspec packs/alpaca_api/spec/services/alpaca_service_vcr_spec.rb

# Run specific test scenarios
bundle exec rspec packs/alpaca_api/spec/services/alpaca_service_vcr_spec.rb -e "account_equity"
bundle exec rspec packs/alpaca_api/spec/services/alpaca_service_vcr_spec.rb -e "place_order"
```

## VCR Cassette Management

### Cassette Organization
Cassettes are stored in `spec/fixtures/vcr_cassettes/alpaca_service/`:
- `account_equity_success.yml` - Successful account equity call
- `account_equity_auth_error.yml` - Authentication error response
- `positions_success.yml` - Successful positions retrieval
- `positions_empty.yml` - Empty positions response
- `place_buy_order_notional.yml` - Successful buy order with notional amount
- `place_sell_order_qty.yml` - Successful sell order with quantity
- And more for various error scenarios...

### Recording New Cassettes

1. **Set up credentials**: Configure valid Alpaca API credentials
2. **Delete old cassettes**: Remove existing `.yml` files if you want to re-record
3. **Run tests**: VCR will make real API calls and record responses
4. **Review cassettes**: Check that sensitive data is properly filtered
5. **Commit**: Add the new cassette files to version control

### Sensitive Data Protection

VCR automatically filters:
- `APCA-API-KEY-ID` headers → `<ALPACA_API_KEY>`
- `APCA-API-SECRET-KEY` headers → `<ALPACA_SECRET_KEY>`

This is configured in `spec/support/vcr.rb`.

## Test Behavior Without Cassettes

When no cassettes exist and no real API credentials are available:
- Tests gracefully handle API errors
- Tests verify that appropriate error messages are raised
- No actual API calls are made (preventing unexpected charges)
- Parameter validation tests still run (no API calls required)

## Best Practices

1. **Use paper trading**: Always use Alpaca's paper trading API for test recordings
2. **Small amounts**: Use minimal trade amounts when recording order placement cassettes
3. **Review before commit**: Always review cassette contents before committing
4. **Test various scenarios**: Record both success and error responses
5. **Keep cassettes minimal**: Only record the data needed for tests

## Environment Configuration

The service uses the same credential resolution as other parts of the system:
1. Environment variables (`ALPACA_API_KEY`, `ALPACA_SECRET_KEY`)
2. Rails credentials (`:alpaca` section)
3. Default test values for development/test environments

Paper trading endpoint is used automatically for non-production environments.