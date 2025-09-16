# frozen_string_literal: true

FactoryBot.define do
  factory :analysis do
    algorithm
    start_date { 1.month.ago.to_date }
    end_date { Date.current }
    status { 'pending' }
    results { {} }
  end
end
