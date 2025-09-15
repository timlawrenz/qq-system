# frozen_string_literal: true

FactoryBot.define do
  factory :algorithm do
    name { 'Test Algorithm' }
    description { 'A test trading strategy for automated analysis' }
  end
end
