# frozen_string_literal: true

module TradingStrategies
  class SectorClassifier
    class << self
      # Returns one of: "defense", "technology", "services"
      def sector_for(ticker)
        sym = ticker.to_s.upcase
        sector = FundamentalDataService.get_sector(sym).to_s
        industry = FundamentalDataService.get_industry(sym).to_s

        return 'defense' if defense_company?(sector, industry)
        return 'technology' if technology_company?(sector)

        'services'
      end

      private

      def defense_company?(sector, industry)
        industry.match?(/aerospace|defense/i) ||
          sector.match?(/industrials/i) && industry.match?(/aerospace/i)
      end

      def technology_company?(sector)
        sector.match?(/technology|communication services/i)
      end
    end
  end
end
