# frozen_string_literal: true

module TradingStrategies
  class MaterialityCalculator
    class << self
      # @param contract_value [Numeric, BigDecimal]
      # @param annual_revenue [Numeric, BigDecimal, nil]
      # @return [Float, nil] materiality percentage
      def calculate(contract_value:, annual_revenue:)
        return nil if annual_revenue.nil?

        revenue = BigDecimal(annual_revenue.to_s)
        return nil if revenue <= 0

        value = BigDecimal(contract_value.to_s)
        ((value / revenue) * 100).to_f
      end
    end
  end
end
