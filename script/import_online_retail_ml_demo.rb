# frozen_string_literal: true

result = OnlineRetailMlDemoImporter.new.call

puts "Imported Online Retail II ML demo into #{result.shop.shopify_domain}"
puts "Customers: #{result.customers_imported}"
puts "Orders: #{result.orders_imported}"
puts "Predictions: #{result.predictions_imported}"
puts "Actions created: #{result.actions_created}"
puts "Actions updated: #{result.actions_updated}"
