FactoryBot.define do
  factory :approval_token do
    association :action
    token_hash  { Digest::SHA256.hexdigest(SecureRandom.hex(32)) }
    expires_at  { 72.hours.from_now }
    consumed_at { nil }

    trait :consumed do
      consumed_at { 1.hour.ago }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end
  end
end
