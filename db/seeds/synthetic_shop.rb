# Synthetic Data Seed — ChurnGuard Development
#
# Creates one realistic Polish e-commerce shop with:
#   - 65 customers (Polish names, real emails)
#   - 280+ orders spanning 15 months
#   - Realistic RFM distribution: ~20% high risk, ~25% medium, ~55% low/active
#   - Revenue range: €25–€850 per order
#
# Run with: bundle exec rails runner db/seeds/synthetic_shop.rb
#
# NOTE: This seed sets RLS context (app.current_shop_id) before inserting
# tenant-scoped records. FORCE ROW LEVEL SECURITY applies even to superusers.

require_relative "golden_fixtures"

puts "=" * 60
puts "ChurnGuard Synthetic Data Seed"
puts "=" * 60

# ─── Polish first names and surnames ──────────────────────────────────────────
POLISH_FIRST_NAMES = %w[
  Maria Anna Katarzyna Małgorzata Agnieszka Barbara Ewa Krystyna Zofia Elżbieta
  Joanna Monika Magdalena Karolina Aleksandra Natalia Paulina Justyna Sylwia Iwona
  Jan Piotr Krzysztof Andrzej Tomasz Marek Marcin Michał Robert Łukasz
  Grzegorz Adam Mateusz Jakub Kamil Bartosz Paweł Rafał Dariusz Wojciech
].freeze

POLISH_LAST_NAMES = %w[
  Kowalski Nowak Wiśniewski Wójcik Kowalczyk Kamiński Lewandowski Zielinski
  Szymański Woźniak Dąbrowski Kozłowski Jankowski Mazur Kwiatkowski Krawczyk
  Piotrowska Grabowska Nowakowska Pawlak Michalska Adamczyk Dudek Zajac
  Wieczorek Kubiak Zawadzki Król Majewski Olszewski Jaworska Pietrzak
  Wysocka Górska Rutkowska Chmielewski Jakubowski Kucharska Walczak Baran
].freeze

POLISH_CITIES = %w[
  Warszawa Kraków Wrocław Poznań Gdańsk Szczecin Bydgoszcz Łódź Lublin Katowice
  Białystok Gdynia Częstochowa Radom Sosnowiec Toruń Kielce Rzeszów Gliwice Zabrze
].freeze

PRODUCT_CATEGORIES = [
  { name: "Casual Wear",      min: 49,  max: 189 },
  { name: "Premium Denim",    min: 129, max: 389 },
  { name: "Accessories",      min: 25,  max: 95  },
  { name: "Footwear",         min: 89,  max: 450 },
  { name: "Outerwear",        min: 199, max: 850 },
  { name: "Sportswear",       min: 59,  max: 249 },
  { name: "Home & Lifestyle", min: 39,  max: 299 },
].freeze

# Seed consistent random data (same run always produces same data)
srand(20260527)

def rand_name
  "#{POLISH_FIRST_NAMES.sample} #{POLISH_LAST_NAMES.sample}"
end

def rand_email(name)
  parts = name.downcase.unicode_normalize(:nfd).gsub(/[^\x00-\x7F]/, "").split
  "#{parts[0]}.#{parts[1]}#{rand(10..99)}@#{%w[gmail.com wp.pl onet.pl interia.pl o2.pl].sample}"
end

def rand_order_amount
  cat = PRODUCT_CATEGORIES.sample
  (cat[:min] + rand(cat[:max] - cat[:min])).to_f.round(2)
end

# ─── Create the shop ──────────────────────────────────────────────────────────
SHOP_DOMAIN = "warsawstyle.myshopify.com"

shop = Shop.find_or_initialize_by(shopify_domain: SHOP_DOMAIN)
shop.shopify_token = "offline_token_placeholder"
shop.save!

puts "\n✓ Shop: #{shop.shopify_domain} (id: #{shop.id})"

# ─── Set RLS context so all subsequent inserts work ───────────────────────────
# FORCE ROW LEVEL SECURITY applies even to superusers in this DB.
ActiveRecord::Base.connection.execute(
  ActiveRecord::Base.sanitize_sql_array(
    ["SELECT set_config('app.current_shop_id', ?, FALSE)", shop.id.to_s]
  )
)
puts "✓ RLS context set to shop_id=#{shop.id}"

# ─── Customer profiles ────────────────────────────────────────────────────────
# Mix of risk profiles:
#  - 13 HIGH risk  (churned: no order in 180+ days)
#  - 17 MEDIUM risk (at-risk: 90–179 days since last order)
#  - 35 ACTIVE/LOW  (recent: <90 days since last order)

CUSTOMER_PROFILES = [
  # HIGH RISK — churned (last order > 180 days ago, few orders)
  { days_since_last: 365, orders: 1,  spend_range: [45,  120] },
  { days_since_last: 320, orders: 1,  spend_range: [89,  89]  },
  { days_since_last: 290, orders: 2,  spend_range: [120, 180] },
  { days_since_last: 275, orders: 1,  spend_range: [55,  55]  },
  { days_since_last: 260, orders: 2,  spend_range: [90,  150] },
  { days_since_last: 245, orders: 1,  spend_range: [200, 200] },
  { days_since_last: 230, orders: 2,  spend_range: [130, 220] },
  { days_since_last: 215, orders: 1,  spend_range: [75,  75]  },
  { days_since_last: 207, orders: 1,  spend_range: [89,  89]  },  # Maria Kowalski profile
  { days_since_last: 200, orders: 2,  spend_range: [100, 200] },
  { days_since_last: 195, orders: 2,  spend_range: [145, 145] }, # Jan Nowak profile
  { days_since_last: 190, orders: 1,  spend_range: [160, 250] },
  { days_since_last: 182, orders: 1,  spend_range: [220, 220] }, # Anna Wiśniewska profile

  # MEDIUM RISK — at-risk (90–179 days, small purchase history)
  { days_since_last: 178, orders: 3,  spend_range: [180, 350] },
  { days_since_last: 165, orders: 2,  spend_range: [220, 380] },
  { days_since_last: 150, orders: 3,  spend_range: [150, 300] },
  { days_since_last: 140, orders: 4,  spend_range: [200, 420] },
  { days_since_last: 130, orders: 2,  spend_range: [250, 380] },
  { days_since_last: 120, orders: 3,  spend_range: [180, 320] },
  { days_since_last: 110, orders: 2,  spend_range: [160, 290] },
  { days_since_last: 105, orders: 3,  spend_range: [200, 350] },
  { days_since_last: 100, orders: 4,  spend_range: [220, 400] },
  { days_since_last:  97, orders: 2,  spend_range: [190, 310] },
  { days_since_last:  95, orders: 2,  spend_range: [210, 210] }, # Piotr Zielinski profile
  { days_since_last:  93, orders: 4,  spend_range: [130, 130] }, # Karolina Dąbrowska profile
  { days_since_last:  92, orders: 3,  spend_range: [180, 320] },
  { days_since_last:  91, orders: 2,  spend_range: [240, 390] },
  { days_since_last:  90, orders: 3,  spend_range: [190, 350] },
  { days_since_last:  88, orders: 1,  spend_range: [890, 890] }, # Tomasz Wójcik profile (high LTV saves from HIGH)

  # LOW/ACTIVE — healthy customers
  { days_since_last:  85, orders: 4,  spend_range: [300, 520] },
  { days_since_last:  80, orders: 5,  spend_range: [380, 680] },
  { days_since_last:  75, orders: 3,  spend_range: [250, 450] },
  { days_since_last:  70, orders: 6,  spend_range: [420, 750] },
  { days_since_last:  65, orders: 4,  spend_range: [320, 560] },
  { days_since_last:  60, orders: 5,  spend_range: [390, 690] },
  { days_since_last:  55, orders: 7,  spend_range: [480, 850] },
  { days_since_last:  50, orders: 5,  spend_range: [350, 620] },
  { days_since_last:  47, orders: 4,  spend_range: [280, 490] },
  { days_since_last:  45, orders: 6,  spend_range: [320, 320] }, # Bartosz Szymański profile
  { days_since_last:  42, orders: 5,  spend_range: [360, 640] },
  { days_since_last:  40, orders: 8,  spend_range: [550, 980] },
  { days_since_last:  38, orders: 6,  spend_range: [410, 730] },
  { days_since_last:  35, orders: 5,  spend_range: [340, 600] },
  { days_since_last:  33, orders: 7,  spend_range: [480, 860] },
  { days_since_last:  30, orders: 5,  spend_range: [750, 750] }, # Zofia Lewandowska profile
  { days_since_last:  28, orders: 6,  spend_range: [430, 760] },
  { days_since_last:  25, orders: 9,  spend_range: [620, 1100] },
  { days_since_last:  22, orders: 7,  spend_range: [490, 870] },
  { days_since_last:  20, orders: 6,  spend_range: [380, 680] },
  { days_since_last:  18, orders: 5,  spend_range: [310, 560] },
  { days_since_last:  16, orders: 8,  spend_range: [540, 960] },
  { days_since_last:  14, orders: 8,  spend_range: [480, 480] }, # Marek Kaminski profile
  { days_since_last:  12, orders: 10, spend_range: [720, 1280] },
  { days_since_last:  10, orders: 9,  spend_range: [640, 1130] },
  { days_since_last:   8, orders: 11, spend_range: [780, 1390] },
  { days_since_last:   7, orders: 12, spend_range: [1840, 1840] }, # Ewa Kowalczyk profile
  { days_since_last:   6, orders: 7,  spend_range: [490, 870] },
  { days_since_last:   5, orders: 8,  spend_range: [560, 990] },
  { days_since_last:   4, orders: 6,  spend_range: [420, 750] },
  { days_since_last:   3, orders: 9,  spend_range: [640, 1130] },
  { days_since_last:   2, orders: 14, spend_range: [980, 1740] },
  { days_since_last:   1, orders: 11, spend_range: [760, 1350] },
].freeze

puts "\nCreating #{CUSTOMER_PROFILES.length} customers with orders..."

customers_created = 0
orders_created = 0
used_names = []

CUSTOMER_PROFILES.each_with_index do |profile, idx|
  # Generate unique name
  name = loop do
    n = rand_name
    break n unless used_names.include?(n)
  end
  used_names << name

  shopify_id = (10_000 + idx + 1).to_s
  email = rand_email(name)
  city = POLISH_CITIES.sample

  # Build orders timeline
  order_dates = []
  base_date = Time.current - profile[:days_since_last].days

  # Spread orders backward in time from the last order
  profile[:orders].times do |i|
    gap_days = i == 0 ? 0 : rand(20..90)
    order_dates << (base_date - (order_dates.last ? (Time.current - order_dates.last) + gap_days.days : 0.days))
  end
  order_dates = order_dates.sort

  # Compute total spent
  order_amounts = profile[:orders].times.map do
    min, max = profile[:spend_range]
    min == max ? min.to_f : (min + rand(max - min)).to_f.round(2)
  end
  total_spent = order_amounts.sum.round(2)

  # Create customer
  customer = Customer.find_or_create_by!(
    shop: shop,
    shopify_customer_id: shopify_id
  ) do |c|
    c.name           = name
    c.email          = email
    c.lifetime_value = total_spent
  end
  customer.update!(lifetime_value: total_spent) if customer.persisted? && customer.lifetime_value != total_spent
  customers_created += 1

  # Create orders
  order_dates.each_with_index do |date, order_idx|
    amount = order_amounts[order_idx] || rand_order_amount
    Order.find_or_create_by!(
      shop: shop,
      shopify_order_id: "#{shopify_id}_#{order_idx + 1}"
    ) do |o|
      o.customer   = customer
      o.amount     = amount
      o.currency   = "EUR"
      o.status     = "paid"
      o.ordered_at = date
    end
    orders_created += 1
  end

  # Create a customers_create event for the first order date
  Event.find_or_create_by!(
    shop: shop,
    event_type: "customers_create",
    occurred_at: order_dates.first
  ) do |e|
    e.customer         = customer
    e.payload          = { "shopify_customer_id" => shopify_id, "email" => email }
    e.shopify_webhook_id = "evt_create_#{shopify_id}"
  end

  # Create orders_paid events
  order_dates.each_with_index do |date, order_idx|
    Event.find_or_create_by!(
      shop: shop,
      shopify_webhook_id: "evt_paid_#{shopify_id}_#{order_idx + 1}"
    ) do |e|
      e.customer   = customer
      e.event_type = "orders_paid"
      e.payload    = {
        "order_id"    => "#{shopify_id}_#{order_idx + 1}",
        "amount"      => order_amounts[order_idx] || rand_order_amount,
        "currency"    => "EUR",
        "customer_id" => shopify_id
      }
      e.occurred_at = date
    end
  end
end

puts "\n#{'-' * 40}"
puts "✓ Customers created: #{customers_created}"
puts "✓ Orders created:    #{orders_created}"
puts "✓ Shop total LTV:    €#{Customer.sum(:lifetime_value).round(2)}"
puts "✓ Shop median LTV:   €#{Customer.order(:lifetime_value).pluck(:lifetime_value)[Customer.count / 2]}"
puts ""
puts "Risk profile:"
puts "  Total customers: #{Customer.count}"

# Quick RFM summary without the full scoring engine (Phase 3)
now = Time.current
high   = Customer.joins(:orders).group(:id)
                 .having("MAX(orders.ordered_at) < ?", now - 180.days).count.length
medium = Customer.joins(:orders).group(:id)
                 .having("MAX(orders.ordered_at) BETWEEN ? AND ?",
                          now - 180.days, now - 90.days).count.length
low    = Customer.count - high - medium

puts "  ~HIGH risk  (>180d no order): #{high}"
puts "  ~MEDIUM risk (90–180d):       #{medium}"
puts "  ~LOW/active (<90d):           #{low}"
puts ""
puts "#{'-' * 40}"
puts "✓ Seed complete. Shop domain: #{SHOP_DOMAIN}"
puts "  Run the scoring engine (Phase 3) to compute official risk_tier values."
puts "=" * 60
