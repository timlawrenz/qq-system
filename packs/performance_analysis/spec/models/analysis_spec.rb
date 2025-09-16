# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analysis do
  describe 'associations' do
    it 'belongs to an algorithm' do
      expect(described_class.reflect_on_association(:algorithm).macro).to eq(:belongs_to)
    end
  end

  describe 'validations' do
    it 'requires a start_date' do
      analysis = build(:analysis, start_date: nil)
      expect(analysis).not_to be_valid
      expect(analysis.errors[:start_date]).to include("can't be blank")
    end

    it 'requires an end_date' do
      analysis = build(:analysis, end_date: nil)
      expect(analysis).not_to be_valid
      expect(analysis.errors[:end_date]).to include("can't be blank")
    end

    it 'requires a status' do
      analysis = build(:analysis, status: nil)
      expect(analysis).not_to be_valid
      expect(analysis.errors[:status]).to include("can't be blank")
    end

    it 'requires end_date to be after start_date' do
      analysis = build(:analysis, start_date: Date.current, end_date: 1.day.ago.to_date)
      expect(analysis).not_to be_valid
      expect(analysis.errors[:end_date]).to include('must be after start date')
    end

    it 'is valid with proper dates' do
      analysis = build(:analysis, start_date: 1.month.ago.to_date, end_date: Date.current)
      expect(analysis).to be_valid
    end

    it 'allows end_date to equal start_date' do
      analysis = build(:analysis, start_date: Date.current, end_date: Date.current)
      expect(analysis).to be_valid
    end
  end

  describe 'state machine' do
    let(:analysis) { create(:analysis) }

    it 'starts with pending status' do
      expect(analysis.status).to eq('pending')
    end

    describe 'start event' do
      it 'transitions from pending to running' do
        expect(analysis.status).to eq('pending')
        analysis.start
        expect(analysis.status).to eq('running')
      end

      it 'cannot transition from running to running' do
        analysis.update!(status: 'running')
        expect(analysis.can_start?).to be false
      end
    end

    describe 'complete event' do
      it 'transitions from running to completed' do
        analysis.update!(status: 'running')
        analysis.complete
        expect(analysis.status).to eq('completed')
      end

      it 'cannot transition from pending to completed' do
        expect(analysis.can_complete?).to be false
      end
    end

    describe 'mark_as_failed event' do
      it 'transitions from pending to failed' do
        analysis.mark_as_failed
        expect(analysis.status).to eq('failed')
      end

      it 'transitions from running to failed' do
        analysis.update!(status: 'running')
        analysis.mark_as_failed
        expect(analysis.status).to eq('failed')
      end

      it 'cannot transition from completed to failed' do
        analysis.update!(status: 'completed')
        expect(analysis.can_mark_as_failed?).to be false
      end
    end

    describe 'retry_analysis event' do
      it 'transitions from failed to pending' do
        analysis.update!(status: 'failed')
        analysis.retry_analysis
        expect(analysis.status).to eq('pending')
      end

      it 'cannot transition from completed to pending' do
        analysis.update!(status: 'completed')
        expect(analysis.can_retry_analysis?).to be false
      end
    end
  end

  describe 'database columns' do
    it 'has the expected columns' do
      expected_columns = %w[algorithm_id start_date end_date status results created_at updated_at]
      expect(described_class.column_names).to include(*expected_columns)
    end

    it 'has default status of pending' do
      analysis = described_class.new
      expect(analysis.status).to eq('pending')
    end

    it 'stores results as jsonb' do
      analysis = create(:analysis, results: { total_return: 15.5, sharpe_ratio: 1.2 })
      analysis.reload
      expect(analysis.results).to eq({ 'total_return' => 15.5, 'sharpe_ratio' => 1.2 })
    end
  end

  describe 'factory' do
    it 'creates a valid analysis' do
      analysis = create(:analysis)
      expect(analysis).to be_persisted
      expect(analysis.algorithm).to be_present
      expect(analysis.start_date).to be_present
      expect(analysis.end_date).to be_present
      expect(analysis.status).to eq('pending')
    end
  end
end
