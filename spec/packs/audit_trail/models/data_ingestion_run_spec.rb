# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditTrail::DataIngestionRun, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      run = build(:data_ingestion_run)
      expect(run).to be_valid
    end

    it 'requires run_id' do
      run = build(:data_ingestion_run, run_id: nil)
      expect(run).not_to be_valid
      expect(run.errors[:run_id]).to include("can't be blank")
    end

    it 'requires task_name' do
      run = build(:data_ingestion_run, task_name: nil)
      expect(run).not_to be_valid
    end

    it 'requires data_source' do
      run = build(:data_ingestion_run, data_source: nil)
      expect(run).not_to be_valid
    end

    it 'requires started_at' do
      run = build(:data_ingestion_run, started_at: nil)
      expect(run).not_to be_valid
    end

    it 'validates run_id uniqueness' do
      create(:data_ingestion_run, run_id: 'test-uuid')
      duplicate = build(:data_ingestion_run, run_id: 'test-uuid')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:run_id]).to include('has already been taken')
    end

    it 'validates status inclusion' do
      run = build(:data_ingestion_run, status: 'invalid')
      expect(run).not_to be_valid
      expect(run.errors[:status]).to include('is not included in the list')
    end
  end

  describe 'state machine' do
    let(:run) { create(:data_ingestion_run, status: 'running') }

    it 'starts in running state' do
      expect(run.status).to eq('running')
    end

    it 'can transition from running to completed' do
      expect { run.complete }.to change(run, :status).from('running').to('completed')
    end

    it 'can transition from running to failed' do
      expect { run.fail }.to change(run, :status).from('running').to('failed')
    end
  end

  describe 'associations' do
    let(:run) { create(:data_ingestion_run) }

    it 'has many data_ingestion_run_records' do
      record1 = create(:data_ingestion_run_record, data_ingestion_run: run)
      record2 = create(:data_ingestion_run_record, data_ingestion_run: run)

      expect(run.data_ingestion_run_records).to include(record1, record2)
    end

    it 'has many api_call_logs' do
      log1 = create(:api_call_log, data_ingestion_run: run)
      log2 = create(:api_call_log, data_ingestion_run: run)

      expect(run.api_call_logs).to include(log1, log2)
    end

    it 'destroys dependent records when deleted' do
      create(:data_ingestion_run_record, data_ingestion_run: run)
      create(:api_call_log, data_ingestion_run: run)

      expect { run.destroy }.to change(AuditTrail::DataIngestionRunRecord, :count).by(-1)
                            .and change(AuditTrail::ApiCallLog, :count).by(-1)
    end
  end

  describe 'scopes' do
    describe '.recent' do
      it 'returns runs from last 24 hours' do
        old_run = create(:data_ingestion_run, started_at: 2.days.ago)
        recent_run = create(:data_ingestion_run, started_at: 1.hour.ago)

        expect(described_class.recent).to include(recent_run)
        expect(described_class.recent).not_to include(old_run)
      end

      it 'orders by started_at descending' do
        older = create(:data_ingestion_run, started_at: 2.hours.ago)
        newer = create(:data_ingestion_run, started_at: 1.hour.ago)

        expect(described_class.recent.first).to eq(newer)
        expect(described_class.recent.last).to eq(older)
      end
    end

    describe '.for_task' do
      it 'filters by task name' do
        congress = create(:data_ingestion_run, task_name: 'data_fetch:congress_daily')
        insider = create(:data_ingestion_run, task_name: 'data_fetch:insider_daily')

        result = described_class.for_task('data_fetch:congress_daily')
        expect(result).to include(congress)
        expect(result).not_to include(insider)
      end
    end

    describe '.for_source' do
      it 'filters by data source' do
        quiver = create(:data_ingestion_run, data_source: 'quiverquant_congress')
        propublica = create(:data_ingestion_run, data_source: 'propublica')

        result = described_class.for_source('quiverquant_congress')
        expect(result).to include(quiver)
        expect(result).not_to include(propublica)
      end
    end

    describe '.successful' do
      it 'returns only completed runs' do
        completed = create(:data_ingestion_run, :completed)
        failed = create(:data_ingestion_run, :failed)
        running = create(:data_ingestion_run, status: 'running')

        result = described_class.successful
        expect(result).to include(completed)
        expect(result).not_to include(failed, running)
      end
    end

    describe '.failed_runs' do
      it 'returns only failed runs' do
        completed = create(:data_ingestion_run, :completed)
        failed = create(:data_ingestion_run, :failed)

        result = described_class.failed_runs
        expect(result).to include(failed)
        expect(result).not_to include(completed)
      end
    end
  end

  describe '#duration_seconds' do
    it 'returns nil when run is still running' do
      run = build(:data_ingestion_run, completed_at: nil, failed_at: nil)
      expect(run.duration_seconds).to be_nil
    end

    it 'calculates duration for completed run' do
      started = Time.current
      completed = started + 45.seconds
      run = build(:data_ingestion_run, started_at: started, completed_at: completed)

      expect(run.duration_seconds).to eq(45)
    end

    it 'calculates duration for failed run' do
      started = Time.current
      failed = started + 30.seconds
      run = build(:data_ingestion_run, started_at: started, failed_at: failed)

      expect(run.duration_seconds).to eq(30)
    end
  end

  describe '#success?' do
    it 'returns true when status is completed' do
      run = build(:data_ingestion_run, status: 'completed')
      expect(run.success?).to be true
    end

    it 'returns false when status is failed' do
      run = build(:data_ingestion_run, status: 'failed')
      expect(run.success?).to be false
    end

    it 'returns false when status is running' do
      run = build(:data_ingestion_run, status: 'running')
      expect(run.success?).to be false
    end
  end
end
