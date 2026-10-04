FactoryBot.define do
  factory :customer do
    association :shop
    sequence(:shopify_customer_id) { |n| (10_000 + n).to_s }
    name            { Faker::Name.name }
    email           { Faker::Internet.email }
    lifetime_value  { Faker::Commerce.price(range: 50..2000) }
    risk_tier       { nil }
  end
end
