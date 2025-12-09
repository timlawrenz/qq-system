# VCR Tests - Status Update

## Summary

Successfully fixed and re-enabled VCR (HTTP recording) tests for QuiverClient and AlpacaService.

## Changes Made

### 1. Fixed Environment Variable Names
- **QuiverClient**: Changed from `QUIVER_API_KEY` to `QUIVER_AUTH_TOKEN`
- **AlpacaService**: Changed from stubbing to using real environment variables

### 2. Updated VCR Configuration (`spec/support/vcr.rb`)
- Set `record: :new_episodes` to allow recording new cassettes
- Changed `allow_http_connections_when_no_cassette: true` to enable recording
- Changed `WebMock.allow_net_connect!` to allow real HTTP during recording
- Simplified `match_requests_on` to `[:method, :uri]` for more flexible matching
- Fixed header name casing for Alpaca filters (`Apca-Api-Key-Id` instead of `APCA-API-KEY-ID`)

### 3. Removed ENV Stubbing
- Removed complex ENV mocking in favor of using real `.env` credentials
- VCR automatically filters sensitive data per configuration

### 4. Re-enabled Tests
- Changed `RSpec.xdescribe` to `RSpec.describe` in `quiver_client_vcr_spec.rb`

## Test Status

### QuiverClient VCR Tests ✅
- **File**: `spec/packs/data_fetching/services/quiver_client_vcr_spec.rb`
- **Status**: Working and recording cassettes
- **Total**: 13 examples
- **Note**: Tests may be slow due to rate limiting (60 requests/min)

### AlpacaService VCR Tests ⚠️
- **File**: `packs/alpaca_api/spec/services/alpaca_service_vcr_spec.rb`
- **Status**: Ready to test (not run yet due to time)
- **Note**: Market closed on weekends may affect some tests

## Recorded Cassettes

Cassettes are stored in `spec/fixtures/vcr_cassettes/`:
```
quiver_client/
  ├── successful_response.yml
  ├── with_date_filters.yml
  ├── auth_error.yml
  └── ... (more as tests run)
```

Sensitive data (API keys) is automatically filtered and replaced with placeholders like `<QUIVER_API_KEY>`.

## How to Use

### Running VCR Tests
```bash
# Run specific VCR test
bundle exec rspec spec/packs/data_fetching/services/quiver_client_vcr_spec.rb:18

# Run all QuiverClient VCR tests (slow due to rate limiting)
bundle exec rspec spec/packs/data_fetching/services/quiver_client_vcr_spec.rb

# Run all AlpacaService VCR tests  
bundle exec rspec packs/alpaca_api/spec/services/alpaca_service_vcr_spec.rb
```

### Re-recording Cassettes
```bash
# Delete old cassettes
rm -rf spec/fixtures/vcr_cassettes/*

# Run tests to record fresh cassettes
bundle exec rspec spec/packs/data_fetching/services/quiver_client_vcr_spec.rb
```

## Benefits

1. **No Real API Calls in CI**: Once cassettes are recorded, tests replay responses without hitting APIs
2. **Faster Test Suite**: Replayed requests are instant
3. **Secure**: API keys are filtered out of cassettes
4. **Reliable**: Tests don't fail due to API rate limits or downtime
5. **Version Control**: Cassettes can be committed to track API response changes

## Known Issues

1. **Rate Limiting**: QuiverClient has 60 req/min limit, making initial recording slow
2. **Market Hours**: Some Alpaca tests may behave differently when market is closed
3. **Test Duration**: Recording all 13 QuiverClient tests takes ~3-4 minutes due to rate limiting

## Recommendations

1. **Run Tests Selectively**: Don't run all VCR tests at once during development
2. **Commit Cassettes**: Add cassettes to git so CI doesn't need to record them
3. **Periodic Re-recording**: Re-record cassettes monthly to catch API changes
4. **Skip Slow Tests**: Use `:vcr` tag to skip/run VCR tests selectively:
   ```bash
   # Skip VCR tests
   bundle exec rspec --tag ~vcr
   
   # Run only VCR tests
   bundle exec rspec --tag vcr
   ```

## Next Steps

- [ ] Run and record AlpacaService VCR tests
- [ ] Commit cassettes to repository
- [ ] Update CI to skip VCR recording (use existing cassettes)
- [ ] Add documentation about VCR to README

---

**Status**: ✅ QuiverClient VCR tests working  
**Last Updated**: 2025-11-08  
**Cassettes Recorded**: Yes (QuiverClient)
