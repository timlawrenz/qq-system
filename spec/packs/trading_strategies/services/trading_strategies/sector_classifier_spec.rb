# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingStrategies::SectorClassifier do
  describe '.sector_for' do
    it 'classifies defense based on sector/industry' do
      allow(TradingStrategies::FundamentalDataService).to receive(:get_sector).and_return('Industrials')
      allow(TradingStrategies::FundamentalDataService).to receive(:get_industry).and_return('Aerospace & Defense')

      expect(described_class.sector_for('LMT')).to eq('defense')
    end

    it 'classifies technology based on sector' do
      allow(TradingStrategies::FundamentalDataService).to receive(:get_sector).and_return('Technology')
      allow(TradingStrategies::FundamentalDataService).to receive(:get_industry).and_return('Software')

      expect(described_class.sector_for('MSFT')).to eq('technology')
    end

    it 'defaults to services' do
      allow(TradingStrategies::FundamentalDataService).to receive(:get_sector).and_return(nil)
      allow(TradingStrategies::FundamentalDataService).to receive(:get_industry).and_return(nil)

      expect(described_class.sector_for('XYZ')).to eq('services')
    end
  end
end
