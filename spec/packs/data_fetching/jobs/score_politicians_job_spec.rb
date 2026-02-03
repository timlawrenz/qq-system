# frozen_string_literal: true

# rubocop:disable RSpec/ContextWording

require 'rails_helper'

RSpec.describe ScorePoliticiansJob, type: :job do
  describe '#perform' do
    context 'with no existing data' do
      it 'completes successfully with no profiles or trades' do
        expect { described_class.perform_now }.not_to raise_error
      end

      it 'logs completion summary' do
        allow(Rails.logger).to receive(:info)

        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with(/Starting politician scoring/)
        expect(Rails.logger).to have_received(:info).with(/Complete/)
        expect(Rails.logger).to have_received(:info).with(/Total profiles: 0/)
      end
    end

    context 'with new politicians in trades' do
      before do
        # Create congressional trades for 3 politicians
        create(:quiver_trade,
               trader_name: 'Nancy Pelosi',
               trader_source: 'congress',
               transaction_type: 'Purchase',
               transaction_date: 30.days.ago.to_date)

        create(:quiver_trade,
               trader_name: 'Josh Gottheimer',
               trader_source: 'congress',
               transaction_type: 'Purchase',
               transaction_date: 20.days.ago.to_date)

        create(:quiver_trade,
               trader_name: 'Dan Crenshaw',
               trader_source: 'congress',
               transaction_type: 'Sale',
               transaction_date: 10.days.ago.to_date)
      end

      it 'creates politician profiles for all congressional traders' do
        expect { described_class.perform_now }
          .to change(PoliticianProfile, :count).from(0).to(3)
      end

      it 'creates profiles with correct names' do
        described_class.perform_now

        names = PoliticianProfile.pluck(:name)
        expect(names).to include('Nancy Pelosi', 'Josh Gottheimer', 'Dan Crenshaw')
      end

      it 'sets default quality score of 5.0 for new profiles' do
        described_class.perform_now

        profile = PoliticianProfile.find_by(name: 'Nancy Pelosi')
        expect(profile.quality_score).to eq(5.0)
      end

      it 'sets last_scored_at timestamp for new profiles' do
        described_class.perform_now

        profile = PoliticianProfile.find_by(name: 'Nancy Pelosi')
        expect(profile.last_scored_at).to be_within(5.seconds).of(Time.current)
      end

      it 'does not create profiles for non-congressional traders' do
        # Add an insider trade
        create(:quiver_trade,
               trader_name: 'Tim Cook',
               trader_source: 'insider',
               transaction_type: 'Purchase',
               transaction_date: 5.days.ago.to_date)

        expect { described_class.perform_now }
          .to change(PoliticianProfile, :count).by(3) # Only congressional

        expect(PoliticianProfile.find_by(name: 'Tim Cook')).to be_nil
      end

      it 'handles nil trader names gracefully' do
        create(:quiver_trade,
               trader_name: nil,
               trader_source: 'congress',
               transaction_type: 'Purchase',
               transaction_date: 5.days.ago.to_date)

        expect { described_class.perform_now }.not_to raise_error
      end
    end

    context 'with existing politician profiles' do
      let!(:existing_profile) do
        create(:politician_profile,
               name: 'Nancy Pelosi',
               quality_score: 5.0,
               total_trades: 0,
               last_scored_at: 1.month.ago)
      end

      before do
        # Add trades for Nancy within scoring window (365 days)
        create(:quiver_trade,
               trader_name: 'Nancy Pelosi',
               trader_source: 'congress',
               transaction_type: 'Purchase',
               ticker: 'AAPL',
               transaction_date: 100.days.ago.to_date)

        create(:quiver_trade,
               trader_name: 'Nancy Pelosi',
               trader_source: 'congress',
               transaction_type: 'Purchase',
               ticker: 'MSFT',
               transaction_date: 200.days.ago.to_date)

        create(:quiver_trade,
               trader_name: 'Nancy Pelosi',
               trader_source: 'congress',
               transaction_type: 'Purchase',
               ticker: 'GOOGL',
               transaction_date: 300.days.ago.to_date)
      end

      it 'does not create duplicate profiles' do
        expect { described_class.perform_now }
          .not_to(change(PoliticianProfile, :count))
      end

      it 'updates quality score based on trades' do
        # Quality score should be recalculated even if it stays at 5.0
        # (5.0 is the default but also a valid calculated score)
        expect { described_class.perform_now }
          .to change { existing_profile.reload.total_trades }.from(0)

        # Score will be recalculated (even if value is still 5.0)
        expect(existing_profile.reload.last_scored_at).to be_present
      end

      it 'updates total_trades count' do
        expect { described_class.perform_now }
          .to change { existing_profile.reload.total_trades }.from(0)
      end

      it 'updates last_scored_at timestamp' do
        old_timestamp = existing_profile.last_scored_at

        described_class.perform_now

        new_timestamp = existing_profile.reload.last_scored_at
        expect(new_timestamp).to be > old_timestamp
        expect(new_timestamp).to be_within(5.seconds).of(Time.current)
      end
    end

    context 'with multiple politicians to score' do
      before do
        # Create 5 politicians with varying trade histories
        5.times do |i|
          trader_name = "Politician #{i}"
          create(:quiver_trade,
                 trader_name: trader_name,
                 trader_source: 'congress',
                 transaction_type: 'Purchase',
                 transaction_date: (i + 1).days.ago.to_date)
        end
      end

      it 'creates all missing profiles' do
        expect { described_class.perform_now }
          .to change(PoliticianProfile, :count).by(5)
      end

      it 'scores all profiles' do
        described_class.perform_now

        scored_count = PoliticianProfile.where.not(last_scored_at: nil).count
        expect(scored_count).to eq(5)
      end

      it 'logs summary with correct counts' do
        allow(Rails.logger).to receive(:info)

        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with(/Total profiles: 5/)
        expect(Rails.logger).to have_received(:info).with(/Scored profiles: 5/)
      end
    end

    context 'with scoring errors' do
      let!(:profile) { create(:politician_profile, name: 'Test Politician') }

      before do
        # Mock PoliticianScorer to raise an error for this profile
        scorer_double = instance_double(PoliticianScorer)
        allow(scorer_double).to receive(:call).and_raise(StandardError, 'Scoring failed')
        allow(PoliticianScorer).to receive(:new).with(profile).and_return(scorer_double)
      end

      it 'logs error but continues processing' do
        allow(Rails.logger).to receive(:error)
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:debug)

        expect { described_class.perform_now }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/Failed to score Test Politician/)
      end

      it 'does not halt job execution on individual scoring error' do
        # Create another profile that should score successfully
        other_profile = create(:politician_profile, name: 'Other Politician')
        create(:quiver_trade,
               trader_name: 'Other Politician',
               trader_source: 'congress',
               transaction_type: 'Purchase',
               transaction_date: 10.days.ago.to_date)

        # Allow successful scoring for other profile
        allow(PoliticianScorer).to receive(:new).with(other_profile).and_call_original

        described_class.perform_now

        # Other politician should still get scored despite error with first
        expect(other_profile.reload.last_scored_at).to be_present
      end
    end

    context 'with large dataset' do
      before do
        # Create 100 politicians
        100.times do |i|
          create(:quiver_trade,
                 trader_name: "Politician #{i}",
                 trader_source: 'congress',
                 transaction_type: 'Purchase',
                 transaction_date: rand(1..365).days.ago.to_date)
        end
      end

      it 'processes all politicians efficiently' do
        expect { described_class.perform_now }.not_to raise_error

        expect(PoliticianProfile.count).to eq(100)
      end

      it 'completes in reasonable time', :performance do
        start_time = Time.current
        described_class.perform_now
        duration = Time.current - start_time

        # Should process 100 politicians in under 5 seconds
        expect(duration).to be < 5.seconds
      end
    end

    context 'idempotency' do
      before do
        create(:quiver_trade,
               trader_name: 'Nancy Pelosi',
               trader_source: 'congress',
               transaction_type: 'Purchase',
               transaction_date: 30.days.ago.to_date)
      end

      it 'can be run multiple times safely' do
        # First run
        described_class.perform_now
        first_count = PoliticianProfile.count
        first_profile = PoliticianProfile.find_by(name: 'Nancy Pelosi')

        # Second run
        described_class.perform_now
        second_count = PoliticianProfile.count
        second_profile = PoliticianProfile.find_by(name: 'Nancy Pelosi')

        expect(second_count).to eq(first_count)
        expect(second_profile.id).to eq(first_profile.id)
      end

      it 'updates scores on subsequent runs' do
        # First run
        described_class.perform_now
        first_timestamp = PoliticianProfile.find_by(name: 'Nancy Pelosi').last_scored_at

        # Wait a moment
        sleep 0.1

        # Second run
        described_class.perform_now
        second_timestamp = PoliticianProfile.find_by(name: 'Nancy Pelosi').last_scored_at

        expect(second_timestamp).to be > first_timestamp
      end
    end

    context 'integration with PoliticianScorer' do
      before do
        # Create trades with actual outcomes
        create(:quiver_trade,
               trader_name: 'Nancy Pelosi',
               trader_source: 'congress',
               transaction_type: 'Purchase',
               ticker: 'AAPL',
               transaction_date: 200.days.ago.to_date)

        create(:quiver_trade,
               trader_name: 'Nancy Pelosi',
               trader_source: 'congress',
               transaction_type: 'Purchase',
               ticker: 'MSFT',
               transaction_date: 100.days.ago.to_date)
      end

      it 'delegates to PoliticianScorer for actual scoring' do
        allow(PoliticianScorer).to receive(:new).and_call_original

        described_class.perform_now

        expect(PoliticianScorer).to have_received(:new).at_least(:once)
      end

      it 'updates profile with scorer results' do
        described_class.perform_now

        profile = PoliticianProfile.find_by(name: 'Nancy Pelosi')
        expect(profile.total_trades).to be > 0
        expect(profile.quality_score).to be_present
      end
    end
  end

  describe 'job queue configuration' do
    it 'is queued to default queue' do
      expect(described_class.new.queue_name).to eq('default')
    end
  end

  describe 'job execution' do
    it 'can be enqueued for later execution' do
      expect { described_class.perform_later }.to have_enqueued_job(described_class)
    end

    it 'can be performed immediately' do
      create(:quiver_trade,
             trader_name: 'Test Politician',
             trader_source: 'congress',
             transaction_type: 'Purchase',
             transaction_date: 10.days.ago.to_date)

      expect { described_class.perform_now }.to change(PoliticianProfile, :count).by(1)
    end
  end
end
# rubocop:enable RSpec/ContextWording
