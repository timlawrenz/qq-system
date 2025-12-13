# frozen_string_literal: true

require 'rails_helper'

# Smoke Test: Daily Trading Workflow End-to-End
# Run with: SMOKE_TEST=true bundle exec rspec spec/smoke/

# rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
RSpec.describe Workflows::ExecuteDailyTrading, 'Smoke Test', skip: ENV['SMOKE_TEST'] != 'true' do
  it 'executes workflow without errors' do
    result = described_class.call(
      trading_mode: 'paper',
      skip_data_fetch: true
    )

    expect(result.success?).to be(true)
    expect(result.account_equity).to be > 0
  end
end
# rubocop:enable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
