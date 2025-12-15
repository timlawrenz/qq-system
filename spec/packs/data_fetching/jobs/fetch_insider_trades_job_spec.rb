# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FetchInsiderTradesJob, type: :job do
  describe '#perform' do
    let(:job) { described_class.new }

    it 'delegates to FetchInsiderTrades with defaults and logs summary' do
      context_double = instance_double('GLCommand::Context',
                                       success?: true,
                                       total_count: 10,
                                       new_count: 7,
                                       updated_count: 3,
                                       error_count: 0,
                                       error_messages: [])

      allow(FetchInsiderTrades).to receive(:call).and_return(context_double)

      expect do
        job.perform
      end.not_to raise_error

      expect(FetchInsiderTrades).to have_received(:call).with(
        start_date: nil,
        end_date: nil,
        lookback_days: nil,
        limit: nil
      )
    end

    it 'raises on failure so retries are triggered' do
      failing_context = instance_double('GLCommand::Context',
                                        success?: false,
                                        full_error_message: 'something went wrong',
                                        error: StandardError.new('boom'))

      allow(FetchInsiderTrades).to receive(:call).and_return(failing_context)

      expect do
        job.perform
      end.to raise_error(StandardError, 'boom')
    end
  end
end
