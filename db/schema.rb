# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_28_192306) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "actions", force: :cascade do |t|
    t.string "action_type", null: false
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.datetime "executed_at"
    t.datetime "expires_at"
    t.boolean "holdout", default: false, null: false
    t.string "model_version"
    t.integer "outcome_window_days"
    t.string "proposed_discount"
    t.string "reason"
    t.decimal "revenue_at_risk", precision: 10, scale: 2
    t.string "risk_tier", null: false
    t.bigint "shop_id", null: false
    t.datetime "skipped_at"
    t.string "status", default: "pending", null: false
    t.decimal "expected_incremental_revenue", precision: 10, scale: 2
    t.string "treatment_key"
    t.decimal "uplift_score", precision: 6, scale: 4
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_actions_on_customer_id"
    t.index ["shop_id", "customer_id"], name: "one_pending_per_customer", unique: true, where: "((status)::text = 'pending'::text)"
    t.index ["shop_id", "holdout"], name: "index_actions_on_shop_id_and_holdout"
    t.index ["shop_id", "model_version"], name: "index_actions_on_shop_id_and_model_version"
    t.index ["shop_id", "treatment_key"], name: "index_actions_on_shop_id_and_treatment_key"
    t.index ["shop_id"], name: "index_actions_on_shop_id"
  end

  create_table "approval_tokens", force: :cascade do |t|
    t.bigint "action_id", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "token_hash", null: false
    t.datetime "updated_at", null: false
    t.index ["action_id"], name: "index_approval_tokens_on_action_id", unique: true
    t.index ["token_hash"], name: "index_approval_tokens_on_token_hash", unique: true
  end

  create_table "customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.date "last_scored_on"
    t.decimal "lifetime_value", precision: 10, scale: 2, default: "0.0"
    t.string "name"
    t.decimal "risk_score", precision: 5, scale: 4
    t.string "risk_tier"
    t.bigint "shop_id", null: false
    t.string "shopify_customer_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "shopify_customer_id"], name: "index_customers_on_shop_id_and_shopify_customer_id", unique: true
    t.index ["shop_id"], name: "index_customers_on_shop_id"
  end

  create_table "events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id"
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.bigint "shop_id", null: false
    t.string "shopify_webhook_id"
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_events_on_customer_id"
    t.index ["shop_id", "event_type"], name: "index_events_on_shop_id_and_event_type"
    t.index ["shop_id"], name: "index_events_on_shop_id"
  end

  create_table "execution_queue_items", force: :cascade do |t|
    t.bigint "action_id", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "last_attempted_at"
    t.string "last_error"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.index ["action_id"], name: "index_execution_queue_items_on_action_id", unique: true
  end

  create_table "orders", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "EUR"
    t.bigint "customer_id", null: false
    t.datetime "ordered_at", null: false
    t.bigint "shop_id", null: false
    t.string "shopify_order_id", null: false
    t.string "status", default: "paid"
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["shop_id", "shopify_order_id"], name: "index_orders_on_shop_id_and_shopify_order_id", unique: true
    t.index ["shop_id"], name: "index_orders_on_shop_id"
  end

  create_table "shops", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "klaviyo_api_key"
    t.string "shopify_domain", null: false
    t.string "shopify_token", null: false
    t.datetime "updated_at", null: false
    t.index ["shopify_domain"], name: "index_shops_on_shopify_domain", unique: true
  end

  create_table "webhook_deduplications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.string "webhook_id", null: false
    t.index ["shop_id", "webhook_id"], name: "index_webhook_deduplications_on_shop_id_and_webhook_id", unique: true
    t.index ["shop_id"], name: "index_webhook_deduplications_on_shop_id"
  end

  add_foreign_key "actions", "customers"
  add_foreign_key "actions", "shops"
  add_foreign_key "approval_tokens", "actions"
  add_foreign_key "customers", "shops"
  add_foreign_key "events", "customers"
  add_foreign_key "events", "shops"
  add_foreign_key "execution_queue_items", "actions"
  add_foreign_key "orders", "customers"
  add_foreign_key "orders", "shops"
  add_foreign_key "webhook_deduplications", "shops"
end
