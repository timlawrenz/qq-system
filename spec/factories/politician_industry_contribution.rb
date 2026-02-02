FactoryBot.define do
  factory :politician_industry_contribution do
    association :politician_profile
    association :industry
    
    cycle { 2024 }
    total_amount { 50_000.0 }
    contribution_count { 200 }
    employer_count { 25 }
    top_employers do
      [
        { 'name' => 'Tech Corp', 'amount' => 10_000, 'count' => 50 },
        { 'name' => 'Software Inc', 'amount' => 8_000, 'count' => 40 }
      ]
    end
    fetched_at { Time.current }
  end
end
