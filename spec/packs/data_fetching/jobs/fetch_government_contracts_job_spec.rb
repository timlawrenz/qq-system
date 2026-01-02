# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FetchGovernmentContractsJob, type: :job do
  describe '#perform' do
    let(:job) { described_class.new }

    it 'delegates to FetchGovernmentContracts with defaults' do
      context_double = double('FetchGovernmentContractsResult',
                              success?: true,
                              total_count: 10,
                              new_count: 7,
                              updated_count: 3,
                              error_count: 0,
                              error_messages: [])

      allow(FetchGovernmentContracts).to receive(:call).and_return(context_double)

      expect { job.perform }.not_to raise_error

      expect(FetchGovernmentContracts).to have_received(:call).with(
        start_date: nil,
        end_date: nil,
        lookback_days: nil,
        limit: nil
      )
    end

    it 'raises on failure so retries are triggered' do
      failing_context = instance_double(GLCommand::Context,
                                        success?: false,
                                        full_error_message: 'something went wrong',
                                        error: StandardError.new('boom'))

      allow(FetchGovernmentContracts).to receive(:call).and_return(failing_context)

      expect { job.perform }.to raise_error(StandardError, 'boom')
    end
  end
end
