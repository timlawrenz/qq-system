# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FetchGovernmentContracts do
  let(:start_date) { Date.parse('2024-01-01') }
  let(:end_date)   { Date.parse('2024-01-31') }
  let(:limit)      { 100 }

  let(:client_double) { instance_double(QuiverClient) }

  let(:base_contract) do
    {
      contract_id: 'ABC-123',
      ticker: 'LMT',
      company: 'Lockheed Martin',
      contract_value: BigDecimal('50000000'),
      award_date: Date.parse('2024-01-10'),
      agency: 'Department of Defense',
      contract_type: 'Services',
      description: 'Test contract',
      disclosed_at: Time.zone.parse('2024-01-11T12:00:00Z')
    }
  end

  before do
    allow(QuiverClient).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:api_calls).and_return([])
  end

  describe '.call' do
    context 'with new contracts' do
      before do
        allow(client_double).to receive(:fetch_government_contracts).and_return([base_contract])
      end

      it 'creates new GovernmentContract records and returns counts' do
        result = described_class.call(start_date: start_date, end_date: end_date, limit: limit)

        expect(result).to be_success
        expect(result.total_count).to eq(1)
        expect(result.new_count).to eq(1)
        expect(result.updated_count).to eq(0)
        expect(result.error_count).to eq(0)
        expect(GovernmentContract.count).to eq(1)

        contract = GovernmentContract.last
        expect(contract.contract_id).to eq('ABC-123')
        expect(contract.ticker).to eq('LMT')
        expect(contract.contract_value.to_d).to eq(BigDecimal('50000000'))
      end
    end

    context 'with existing contracts (deduplication)' do
      before do
        GovernmentContract.create!(
          contract_id: 'ABC-123',
          ticker: 'LMT',
          company: 'Lockheed Martin',
          contract_value: 25_000_000,
          award_date: Date.parse('2024-01-10'),
          agency: 'Department of Defense'
        )

        allow(client_double).to receive(:fetch_government_contracts).and_return(
          [
            base_contract.merge(contract_value: BigDecimal('60000000')),
            base_contract.merge(contract_id: 'XYZ-999', ticker: 'NOC')
          ]
        )
      end

      it 'updates existing record by contract_id and creates new ones' do
        result = described_class.call(start_date: start_date, end_date: end_date, limit: limit)

        expect(result).to be_success
        expect(result.total_count).to eq(2)
        expect(result.new_count).to eq(1)
        expect(result.updated_count).to eq(1)

        expect(GovernmentContract.count).to eq(2)
        expect(GovernmentContract.find_by(contract_id: 'ABC-123').contract_value.to_d).to eq(BigDecimal('60000000'))
      end
    end

    context 'with invalid contracts' do
      before do
        allow(client_double).to receive(:fetch_government_contracts).and_return(
          [
            base_contract.merge(award_date: nil),
            base_contract.merge(contract_value: 0),
            base_contract.merge(contract_id: nil)
          ]
        )
      end

      it 'skips invalid contracts and creates no records' do
        result = described_class.call(start_date: start_date, end_date: end_date, limit: limit)

        expect(result).to be_success
        expect(result.total_count).to eq(3)
        expect(result.new_count).to eq(0)
        expect(result.updated_count).to eq(0)
        expect(GovernmentContract.count).to eq(0)
      end
    end
  end
end
