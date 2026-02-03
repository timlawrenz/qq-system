# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuiverClient, :vcr, type: :service do
  let(:client) { described_class.new }

  describe '#fetch_insider_trades', vcr: { cassette_name: 'quiver_client/insider_trades' } do
    it 'fetches real insider trades data' do
      result = client.fetch_insider_trades(limit: 5)

      expect(result).to be_an(Array)
    end

    it 'returns trades with expected structure' do
      result = client.fetch_insider_trades(limit: 5)
      first_trade = result.first

      if result.any?
        expect(first_trade).to have_key(:ticker)
        expect(first_trade).to have_key(:trader_name)
        expect(first_trade).to have_key(:trader_source)
        expect(first_trade).to have_key(:transaction_date)
        expect(first_trade).to have_key(:transaction_type)
        expect(first_trade).to have_key(:trade_size_usd)
        expect(first_trade).to have_key(:disclosed_at)
        expect(first_trade).to have_key(:relationship)
        expect(first_trade).to have_key(:shares_held)
      end
    end
  end
end
