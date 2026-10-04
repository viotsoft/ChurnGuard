class CreateChurnguardSchema < ActiveRecord::Migration[8.1]
  def up
    # ─── customers ────────────────────────────────────────────────────────────
    create_table :customers do |t|
      t.references :shop, null: false, foreign_key: true, index: true
      t.string  :shopify_customer_id, null: false
      t.string  :email
      t.string  :name
      t.decimal :lifetime_value, precision: 10, scale: 2, default: "0.0"
      t.string  :risk_tier   # 'high' | 'medium' | 'low' | nil (unscored)
      t.decimal :risk_score,  precision: 5, scale: 4  # 0.0000 – 1.0000
      t.date    :last_scored_on
      t.timestamps
    end
    add_index :customers, [:shop_id, :shopify_customer_id], unique: true

    # ─── orders ───────────────────────────────────────────────────────────────
    create_table :orders do |t|
      t.references :shop,     null: false, foreign_key: true, index: true
      t.references :customer, null: false, foreign_key: true, index: true
      t.string  :shopify_order_id, null: false
      t.decimal :amount,      precision: 10, scale: 2, null: false
      t.string  :currency,    default: "EUR"
      t.string  :status,      default: "paid"  # 'paid' | 'cancelled' | 'refunded'
      t.datetime :ordered_at, null: false
      t.timestamps
    end
    add_index :orders, [:shop_id, :shopify_order_id], unique: true

    # ─── events ───────────────────────────────────────────────────────────────
    # Normalized behavioral events ingested from Shopify webhooks
    create_table :events do |t|
      t.references :shop,     null: false, foreign_key: true, index: true
      t.references :customer, null: true,  foreign_key: true, index: true
      t.string  :event_type,  null: false  # 'orders_paid' | 'orders_cancelled' | 'customers_create'
      t.jsonb   :payload,     null: false, default: {}
      t.string  :shopify_webhook_id  # stored for deduplication reference
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :events, [:shop_id, :event_type]

    # ─── webhook_deduplications ───────────────────────────────────────────────
    # Guards against Shopify re-delivering the same webhook (idempotency)
    create_table :webhook_deduplications do |t|
      t.references :shop, null: false, foreign_key: true, index: true
      t.string :webhook_id, null: false
      t.timestamps
    end
    add_index :webhook_deduplications, [:shop_id, :webhook_id], unique: true

    # ─── actions ──────────────────────────────────────────────────────────────
    # Proposed retention actions awaiting owner approval
    create_table :actions do |t|
      t.references :shop,     null: false, foreign_key: true, index: true
      t.references :customer, null: false, foreign_key: true, index: true
      t.string  :action_type,      null: false  # 'klaviyo_campaign' | 'discount_code'
      t.string  :status,           null: false, default: "pending"
                                   # pending | approved | skipped | expired | executed | failed
      t.string  :risk_tier,        null: false  # 'high' | 'medium' at time of scoring
      t.decimal :revenue_at_risk,  precision: 10, scale: 2  # estimated monthly LTV at stake
      t.string  :proposed_discount  # e.g. "15%OFF_BIRTHDAY"
      t.string  :reason            # human-readable risk reason for approval email
      t.datetime :expires_at       # 72h from creation — token expiry drives this
      t.datetime :approved_at
      t.datetime :skipped_at
      t.datetime :executed_at
      t.timestamps
    end
    # Partial unique index: only one pending action per customer per shop at a time
    # Atomic prevention of duplicate pending actions (race-proof at DB level)
    add_index :actions, [:shop_id, :customer_id],
              unique: true,
              where: "status = 'pending'",
              name: "one_pending_per_customer"

    # ─── approval_tokens ──────────────────────────────────────────────────────
    # Single-use signed JWTs for one-tap approval email links
    create_table :approval_tokens do |t|
      t.references :action, null: false, foreign_key: true, index: { unique: true }
      t.string   :token_hash, null: false  # SHA-256 of the JWT (never store raw JWT)
      t.datetime :expires_at, null: false  # 72h from issuance
      t.datetime :consumed_at             # set on first use (approve OR skip)
      t.timestamps
    end
    add_index :approval_tokens, :token_hash, unique: true

    # ─── execution_queue_items ────────────────────────────────────────────────
    # Tracks Klaviyo execution attempts for observability + DLQ
    create_table :execution_queue_items do |t|
      t.references :action, null: false, foreign_key: true, index: { unique: true }
      t.string  :status,    null: false, default: "queued"
                            # queued | processing | completed | failed | dead
      t.integer :attempts,  null: false, default: 0
      t.string  :last_error
      t.datetime :last_attempted_at
      t.timestamps
    end

    # ─── Postgres RLS: enable on all tenant tables ─────────────────────────
    # Row-level security ensures Shop A can NEVER read Shop B's data.
    # Application sets: SET app.current_shop_id = <id> per request/job.
    %w[customers orders events actions approval_tokens execution_queue_items
       webhook_deduplications].each do |table|
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"
    end

    # RLS policies: each row's shop_id must match the session variable
    execute <<~SQL
      CREATE POLICY shop_isolation ON customers
        USING (shop_id = current_setting('app.current_shop_id', TRUE)::bigint);
    SQL
    execute <<~SQL
      CREATE POLICY shop_isolation ON orders
        USING (shop_id = current_setting('app.current_shop_id', TRUE)::bigint);
    SQL
    execute <<~SQL
      CREATE POLICY shop_isolation ON events
        USING (shop_id = current_setting('app.current_shop_id', TRUE)::bigint);
    SQL
    execute <<~SQL
      CREATE POLICY shop_isolation ON webhook_deduplications
        USING (shop_id = current_setting('app.current_shop_id', TRUE)::bigint);
    SQL
    execute <<~SQL
      CREATE POLICY shop_isolation ON actions
        USING (shop_id = current_setting('app.current_shop_id', TRUE)::bigint);
    SQL
    # approval_tokens and execution_queue_items are accessed via action joins;
    # their shop_id is implicit through the action FK — RLS on actions covers them.
    # Direct access policies for belt-and-suspenders:
    execute <<~SQL
      CREATE POLICY shop_isolation ON approval_tokens
        USING (
          action_id IN (
            SELECT id FROM actions
            WHERE shop_id = current_setting('app.current_shop_id', TRUE)::bigint
          )
        );
    SQL
    execute <<~SQL
      CREATE POLICY shop_isolation ON execution_queue_items
        USING (
          action_id IN (
            SELECT id FROM actions
            WHERE shop_id = current_setting('app.current_shop_id', TRUE)::bigint
          )
        );
    SQL
  end

  def down
    %w[customers orders events actions approval_tokens execution_queue_items
       webhook_deduplications].each do |table|
      execute "DROP POLICY IF EXISTS shop_isolation ON #{table}"
      execute "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY"
    end

    drop_table :execution_queue_items
    drop_table :approval_tokens
    remove_index :actions, name: "one_pending_per_customer"
    drop_table :actions
    drop_table :webhook_deduplications
    drop_table :events
    drop_table :orders
    drop_table :customers
  end
end
