FactoryBot.define do
  factory :sandbox_user do
    sequence(:email) { |n| "sandbox-user-#{n}@example.com" }
  end
end
