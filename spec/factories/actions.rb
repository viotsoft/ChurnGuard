FactoryBot.define do
  factory :action do
    association :shop
    association :customer
    action_type       { "klaviyo_campaign" }
    status            { "pending" }
    risk_tier         { "high" }
    revenue_at_risk   { 89.99 }
    proposed_discount { "15%" }
    reason            { "Customer hasn't ordered in over 6 months" }
    expires_at        { 72.hours.from_now }

    trait :medium do
      risk_tier         { "medium" }
      proposed_discount { "10%" }
      revenue_at_risk   { 210.00 }
    end

    trait :uplift_v3 do
      treatment_key                  { "winback_15" }
      uplift_score                   { 0.184 }
      expected_incremental_revenue   { 42.50 }
      model_version                  { UpliftDecisionEngine::MODEL_VERSION }
      holdout                        { false }
      outcome_window_days            { UpliftDecisionEngine::OUTCOME_WINDOW_DAYS }
      reason                         { "Uplift V3 estimates +18.4% incremental purchase lift." }
    end

    trait :approved do
      status      { "approved" }
      approved_at { Time.current }
    end

    trait :skipped do
      status     { "skipped" }
      skipped_at { Time.current }
    end

    trait :expired do
      status     { "expired" }
      expires_at { 2.days.ago }
    end

    trait :executed do
      status      { "executed" }
      executed_at { Time.current }
    end

    trait :overdue do
      # Still pending but past expiry (target for TokenExpiryJob)
      status     { "pending" }
      expires_at { 1.hour.ago }
    end
  end
end
