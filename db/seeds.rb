# Seeds are environment-gated to prevent accidental production data seeding.
# In development, this loads golden fixtures for testing the scoring engine.

if Rails.env.development? || Rails.env.test?
  require_relative "seeds/golden_fixtures"
  puts "Golden fixtures defined (#{GOLDEN_FIXTURES.length} profiles)."
  puts "Use spec/scoring/golden_fixtures_spec.rb to verify RFM scoring."
  puts "Median LTV used in scoring: €#{FIXTURE_MEDIAN_LTV}"
end
