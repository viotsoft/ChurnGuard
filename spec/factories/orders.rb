FactoryBot.define do
  factory :order do
    association :shop
    association :customer
    sequence(:shopify_order_id) { |n| "order_#{n}" }
    amount      { Faker::Commerce.price(range: 30..500) }
    currency    { "EUR" }
    status      { "paid" }
    ordered_at  { Faker::Time.between(from: 400.days.ago, to: Time.current) }
  end
end
