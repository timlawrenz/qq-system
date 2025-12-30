# frozen_string_literal: true

class TradingDashboardController < ApplicationController
  def index
    result = TradingDashboard::FetchTradingDashboardSnapshot.call

    @metrics = result.success? ? result.metrics : { state: 'error' }
    @error_message = result.success? ? nil : result.errors.full_messages.join(', ')

    render :index, layout: false
  end
end
