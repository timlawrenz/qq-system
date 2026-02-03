# frozen_string_literal: true

module TradingDashboard
  class MetricCardComponent < ViewComponent::Base
    def initialize(label:, value:, sublabel: nil)
      super()
      @label = label
      @value = value
      @sublabel = sublabel
    end
  end
end
