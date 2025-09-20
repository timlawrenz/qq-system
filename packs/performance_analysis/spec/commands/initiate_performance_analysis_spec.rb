# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InitiatePerformanceAnalysis, type: :command do
  let(:algorithm) { create(:algorithm) }
  let(:start_date) { Date.parse('2024-01-01') }
  let(:end_date) { Date.parse('2024-01-05') }

  describe 'validations' do
    context 'when algorithm_id is invalid' do
      it 'fails with validation error' do
        result = described_class.call(
          algorithm_id: 99_999,
          start_date: start_date,
          end_date: end_date
        )

        expect(result).to be_failure
        expect(result.errors[:algorithm_id]).to include('not found')
      end
    end

    context 'when required parameters are missing' do
      it 'fails when algorithm_id is missing' do
        result = described_class.call(
          start_date: start_date,
          end_date: end_date
        )

        expect(result).to be_failure
      end

      it 'fails when start_date is missing' do
        result = described_class.call(
          algorithm_id: algorithm.id,
          end_date: end_date
        )

        expect(result).to be_failure
      end

      it 'fails when end_date is missing' do
        result = described_class.call(
          algorithm_id: algorithm.id,
          start_date: start_date
        )

        expect(result).to be_failure
      end
    end

    context 'when date range is invalid' do
      it 'fails when end_date is before start_date' do
        result = described_class.call(
          algorithm_id: algorithm.id,
          start_date: end_date,
          end_date: start_date
        )

        expect(result).to be_failure
        expect(result.errors[:end_date]).to include('must be after start date')
      end
    end
  end

  describe 'successful execution' do
    it 'succeeds and delegates to EnqueueAnalysePerformanceJob' do
      expect(EnqueueAnalysePerformanceJob).to receive(:call).with(
        algorithm: algorithm,
        start_date: start_date,
        end_date: end_date
      ).and_call_original

      result = described_class.call(
        algorithm_id: algorithm.id,
        start_date: start_date,
        end_date: end_date
      )

      expect(result).to be_success
      expect(result.analysis).to be_persisted
      expect(result.analysis.algorithm_id).to eq(algorithm.id)
      expect(result.analysis.start_date).to eq(start_date)
      expect(result.analysis.end_date).to eq(end_date)
      expect(result.analysis.status).to eq('pending')
    end

    it 'enqueues a background job for analysis' do
      expect(AnalysePerformanceJob).to receive(:perform_later).with(kind_of(Integer))

      result = described_class.call(
        algorithm_id: algorithm.id,
        start_date: start_date,
        end_date: end_date
      )

      expect(result).to be_success
    end
  end
end
