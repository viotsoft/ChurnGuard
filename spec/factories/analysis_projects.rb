FactoryBot.define do
  factory :analysis_project do
    association :sandbox_user
    sequence(:name) { |n| "Analysis #{n}" }
    status { "ready" }
    mode { "semi_synthetic" }
    raw_expires_at { 24.hours.from_now }
    results_expires_at { 30.days.from_now }
  end
end
