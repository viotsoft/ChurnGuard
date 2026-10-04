FactoryBot.define do
  factory :shop do
    sequence(:shopify_domain) { |n| "test-shop-#{n}.myshopify.com" }
    shopify_token   { "test_token_#{SecureRandom.hex(8)}" }
    klaviyo_api_key { "pk_test_#{SecureRandom.hex(16)}" }
  end
end
