# frozen_string_literal: true

module TradingDashboard
  class PositionsTableComponent < ViewComponent::Base
    def initialize(positions:)
      super()
      @positions = Array(positions)
    end
  end
end
