# VCR Configuration

This project uses VCR (Video Cassette Recorder) to record and replay HTTP interactions for testing external APIs.

## Overview

VCR is configured to:
- Record HTTP interactions with external APIs during tests
- Replay recorded interactions on subsequent test runs
- Filter sensitive data like API keys
- Support different recording modes for development vs production

## Configuration

VCR is configured in `spec/support/vcr.rb` with the following settings:

- **Cassette library**: `spec/fixtures/vcr_cassettes/`
- **Hook**: WebMock 
- **Default record mode**: `:once` (records new interactions only once)
- **Request matching**: Method, URI, query parameters, and request body
- **Sensitive data filtering**: API keys are automatically filtered and replaced with `<QUIVER_API_KEY>`

## Usage

### Basic Usage

```ruby
# In spec files, use the :vcr metadata
describe MyApiClient, :vcr do
  it 'fetches data from API', vcr: { cassette_name: 'my_api/success' } do
    # This will record the HTTP interaction to spec/fixtures/vcr_cassettes/my_api/success.yml
    result = MyApiClient.new.fetch_data
    expect(result).to be_present
  end
end
```

### Recording New Cassettes

1. Delete existing cassette files if you need to re-record
2. Run the tests - VCR will make real HTTP requests and record them
3. Commit the new cassette files to version control

### Cassette Organization

Cassettes are organized by service/client:
- `spec/fixtures/vcr_cassettes/quiver_client/` - QuiverClient API interactions
- `spec/fixtures/vcr_cassettes/alpaca_client/` - AlpacaClient API interactions (future)

## Sensitive Data Protection

All API keys and sensitive data are automatically filtered:
- Authorization headers containing Bearer tokens are replaced with `<QUIVER_API_KEY>`
- Add additional filters in `spec/support/vcr.rb` as needed

## Best Practices

1. **Descriptive cassette names**: Use clear, descriptive names for cassettes
2. **Minimal data**: Record only the minimal data needed for tests
3. **Error scenarios**: Create cassettes for both success and error cases
4. **Stable data**: Use fixed dates and predictable data in cassettes
5. **Review cassettes**: Review cassette contents before committing to ensure no sensitive data

## Troubleshooting

### VCR::Errors::UnhandledHTTPRequestError

This error occurs when VCR encounters an HTTP request that doesn't match any recorded cassette. Solutions:

1. Check the cassette name matches the test
2. Ensure request parameters match exactly
3. Delete and re-record the cassette if the API changed
4. Use more lenient request matching if needed

### Network Timeouts

VCR can't simulate network timeouts. For timeout testing, stub the HTTP client directly:

```ruby
it 'handles timeouts' do
  allow(client.connection).to receive(:get).and_raise(Faraday::TimeoutError)
  expect { client.fetch_data }.to raise_error(StandardError, /timeout/)
end
```