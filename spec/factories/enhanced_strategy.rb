# frozen_string_literal: true

FactoryBot.define do
  factory :politician_profile do
    sequence(:name) { |n| "Politician #{n}" }
    sequence(:bioguide_id) { |n| "P#{n.to_s.rjust(6, '0')}" }
    quality_score { nil }
    total_trades { nil }
    winning_trades { nil }
    average_return { nil }
    last_scored_at { nil }

    trait :with_quality_score do
      quality_score { rand(3.0..10.0).round(2) }
      total_trades { rand(10..50) }
      winning_trades { (total_trades * 0.6).to_i }
      average_return { rand(5.0..15.0).round(2) }
      last_scored_at { 1.day.ago }
    end

    trait :high_quality do
      quality_score { rand(7.5..10.0).round(2) }
      total_trades { rand(20..50) }
      winning_trades { (total_trades * 0.75).to_i }
      average_return { rand(10.0..20.0).round(2) }
      last_scored_at { 1.day.ago }
    end

    trait :low_quality do
      quality_score { rand(0.0..4.0).round(2) }
      total_trades { rand(10..30) }
      winning_trades { (total_trades * 0.3).to_i }
      average_return { rand(-5.0..5.0).round(2) }
      last_scored_at { 1.day.ago }
    end

    trait :needs_scoring do
      last_scored_at { 2.months.ago }
    end
  end

  factory :committee do
    sequence(:code) { |n| "COM#{n.to_s.rjust(3, '0')}" }
    sequence(:name) { |n| "Committee #{n}" }
    chamber { %w[house senate joint].sample }

    trait :house do
      chamber { 'house' }
    end

    trait :senate do
      chamber { 'senate' }
    end

    trait :with_industries do
      transient do
        industry_count { 3 }
      end

      after(:create) do |committee, evaluator|
        create_list(:industry, evaluator.industry_count).each do |industry|
          create(:committee_industry_mapping, committee: committee, industry: industry)
        end
      end
    end
  end

  factory :committee_membership do
    politician_profile
    committee
    start_date { 1.year.ago }
    end_date { nil }

    trait :active do
      end_date { nil }
    end

    trait :expired do
      start_date { 2.years.ago }
      end_date { 6.months.ago }
    end
  end

  factory :industry do
    sequence(:name) { |n| "Industry #{n}" }
    description { "Description for #{name}" }

    trait :technology do
      name { 'Technology' }
      description { 'Software, hardware, and technology services' }
    end

    trait :healthcare do
      name { 'Healthcare' }
      description { 'Healthcare services, pharmaceuticals, and medical devices' }
    end

    trait :finance do
      name { 'Financial Services' }
      description { 'Banking, insurance, and financial services' }
    end
  end

  factory :committee_industry_mapping do
    committee
    industry
  end
end
