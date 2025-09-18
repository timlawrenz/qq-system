# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnqueueAnalysePerformanceJob, type: :command do
  let(:algorithm) { create(:algorithm) }
  let(:start_date) { Date.parse('2024-01-01') }
  let(:end_date) { Date.parse('2024-01-05') }

  describe 'validations' do
    context 'when end_date is before start_date' do
      it 'fails with validation error' do
        result = described_class.call(
          algorithm: algorithm,
          start_date: end_date,
          end_date: start_date
        )

        expect(result).to be_failure
        expect(result.errors.full_messages).to include('End date must be after start date')
      end
    end

    context 'when required parameters are missing' do
      it 'fails when algorithm is missing' do
        result = described_class.call(
          start_date: start_date,
          end_date: end_date
        )

        expect(result).to be_failure
      end

      it 'fails when start_date is missing' do
        result = described_class.call(
          algorithm: algorithm,
          end_date: end_date
        )

        expect(result).to be_failure
      end

      it 'fails when end_date is missing' do
        result = described_class.call(
          algorithm: algorithm,
          start_date: start_date
        )

        expect(result).to be_failure
      end
    end

    context 'when parameters have wrong types' do
      it 'fails when algorithm is not an Algorithm object' do
        result = described_class.call(
          algorithm: 'not_an_algorithm',
          start_date: start_date,
          end_date: end_date
        )

        expect(result).to be_failure
      end

      it 'fails when start_date is not a Date object' do
        result = described_class.call(
          algorithm: algorithm,
          start_date: 'not_a_date',
          end_date: end_date
        )

        expect(result).to be_failure
      end

      it 'fails when end_date is not a Date object' do
        result = described_class.call(
          algorithm: algorithm,
          start_date: start_date,
          end_date: 'not_a_date'
        )

        expect(result).to be_failure
      end
    end
  end

  describe 'successful execution' do
    it 'succeeds and creates an Analysis record' do
      expect(AnalysePerformanceJob).to receive(:perform_later)

      result = described_class.call(
        algorithm: algorithm,
        start_date: start_date,
        end_date: end_date
      )

      expect(result).to be_success

      analysis = result.analysis
      expect(analysis).to be_persisted
      expect(analysis.algorithm_id).to eq(algorithm.id)
      expect(analysis.start_date).to eq(start_date)
      expect(analysis.end_date).to eq(end_date)
      expect(analysis.status).to eq('pending')
    end

    it 'enqueues the background job' do
      expect(AnalysePerformanceJob).to receive(:perform_later).with(kind_of(Integer))

      result = described_class.call(
        algorithm: algorithm,
        start_date: start_date,
        end_date: end_date
      )

      expect(result).to be_success
    end
  end
end
