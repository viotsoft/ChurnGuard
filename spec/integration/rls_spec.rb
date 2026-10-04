# spec/integration/rls_spec.rb
#
# Row-Level Security isolation tests.
#
# Verifies at the database level that a shop session cannot read another shop's
# rows. Tests run within DatabaseCleaner transactions so all DB changes roll back.
#
# Two levels of testing:
#
#   1. Policy existence — asserts the RLS policy is configured on every tenant table.
#      Works regardless of the DB user's privilege level.
#
#   2. Actual isolation — asserts queries as a non-superuser are filtered to only
#      the current shop's rows. Uses `SET LOCAL ROLE churnguard_rls_test` to drop
#      superuser privileges within the test transaction.
#
# NOTE: The test DB user (typically a superuser) bypasses RLS even with
# FORCE ROW LEVEL SECURITY. Level-2 tests create a non-privileged role and
# switch to it via SET LOCAL ROLE (which is automatically reverted by
# DatabaseCleaner's transaction rollback).

require "rails_helper"

RSpec.describe "Row-Level Security", type: :integration do
  # ── Helpers ────────────────────────────────────────────────────────────────

  # Tenant tables that must have RLS enabled and a shop_isolation policy.
  TENANT_TABLES = %w[customers orders events actions webhook_deduplications
                     approval_tokens execution_queue_items].freeze

  # Non-superuser role used for actual isolation tests.
  # Created once per suite in the before(:suite) hook below.
  RLS_TEST_ROLE = "churnguard_rls_test"

  def conn
    ActiveRecord::Base.connection
  end

  # Execute a block as the non-privileged application role within the current
  # DatabaseCleaner transaction. The role change is local to the transaction and
  # rolls back automatically when the test finishes.
  def as_app_role
    conn.execute("SET LOCAL ROLE #{RLS_TEST_ROLE}")
    yield
  ensure
    conn.execute("RESET ROLE")
  end

  # ── One-time setup ─────────────────────────────────────────────────────────

  before(:all) do
    c = ActiveRecord::Base.connection
    # Create the non-superuser role if it doesn't already exist
    c.execute(<<~SQL)
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{RLS_TEST_ROLE}') THEN
          CREATE ROLE #{RLS_TEST_ROLE};
        END IF;
      END
      $$;
    SQL

    # Grant DML access on all application tables + sequences
    c.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{RLS_TEST_ROLE}")
    c.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{RLS_TEST_ROLE}")
  end

  # ── Level 1: Policy existence ──────────────────────────────────────────────

  describe "RLS policy existence" do
    TENANT_TABLES.each do |table|
      it "has RLS enabled on #{table}" do
        result = conn.execute(<<~SQL).first
          SELECT relrowsecurity AS rls_enabled
          FROM pg_class
          WHERE relname = '#{table}'
        SQL
        expect(result["rls_enabled"]).to eq(true),
          "Expected RLS to be enabled on #{table}. " \
          "Run the migration or check ENABLE ROW LEVEL SECURITY."
      end

      it "has a shop_isolation policy on #{table}" do
        result = conn.execute(<<~SQL).first
          SELECT COUNT(*) AS cnt
          FROM pg_policies
          WHERE tablename = '#{table}'
            AND policyname = 'shop_isolation'
        SQL
        expect(result["cnt"].to_i).to be >= 1,
          "Expected a shop_isolation policy on #{table}."
      end
    end
  end

  # ── Level 2: Actual isolation as non-superuser ────────────────────────────

  describe "cross-shop data isolation" do
    let(:shop_a) { create(:shop) }
    let(:shop_b) { create(:shop) }
    let!(:customer_a) { RlsContext.set!(shop_a.id); create(:customer, shop: shop_a) }
    let!(:customer_b) { RlsContext.set!(shop_b.id); create(:customer, shop: shop_b) }

    it "Shop A context sees Shop A customers and not Shop B" do
      as_app_role do
        RlsContext.set!(shop_a.id)
        visible_ids = conn.execute("SELECT id FROM customers").map { |r| r["id"].to_i }
        expect(visible_ids).to include(customer_a.id)
        expect(visible_ids).not_to include(customer_b.id)
      end
    end

    it "Shop B context sees Shop B customers and not Shop A" do
      as_app_role do
        RlsContext.set!(shop_b.id)
        visible_ids = conn.execute("SELECT id FROM customers").map { |r| r["id"].to_i }
        expect(visible_ids).to include(customer_b.id)
        expect(visible_ids).not_to include(customer_a.id)
      end
    end

    it "no context (cleared) blocks all rows" do
      as_app_role do
        RlsContext.clear!
        count = conn.execute("SELECT COUNT(*) AS cnt FROM customers").first["cnt"].to_i
        expect(count).to eq(0),
          "Expected 0 rows when no RLS context is set, got #{count}. " \
          "FORCE ROW LEVEL SECURITY may not be configured correctly."
      end
    end

    it "switching context from A to B changes visible rows" do
      as_app_role do
        RlsContext.set!(shop_a.id)
        before_switch = conn.execute("SELECT id FROM customers").map { |r| r["id"].to_i }

        RlsContext.set!(shop_b.id)
        after_switch = conn.execute("SELECT id FROM customers").map { |r| r["id"].to_i }

        expect(before_switch).not_to eq(after_switch)
        expect(before_switch).to include(customer_a.id)
        expect(after_switch).to include(customer_b.id)
      end
    end
  end

  # ── Level 3: RlsContext API ────────────────────────────────────────────────

  describe "RlsContext" do
    let(:shop) { create(:shop) }

    describe ".set!" do
      it "persists the shop_id on the connection" do
        RlsContext.set!(shop.id)
        expect(RlsContext.current_shop_id).to eq(shop.id)
      end
    end

    describe ".clear!" do
      it "removes the shop_id so current_shop_id returns nil" do
        RlsContext.set!(shop.id)
        RlsContext.clear!
        expect(RlsContext.current_shop_id).to be_nil
      end
    end

    describe ".set (block form)" do
      let(:shop_b) { create(:shop) }

      it "restores the previous context after the block" do
        RlsContext.set!(shop.id)

        RlsContext.set(shop_b.id) do
          expect(RlsContext.current_shop_id).to eq(shop_b.id)
        end

        expect(RlsContext.current_shop_id).to eq(shop.id)
      end

      it "restores context even if the block raises" do
        RlsContext.set!(shop.id)

        expect {
          RlsContext.set(shop_b.id) { raise "boom" }
        }.to raise_error("boom")

        expect(RlsContext.current_shop_id).to eq(shop.id)
      end
    end
  end

  # ── Level 4: AR association isolation ─────────────────────────────────────

  describe "ActiveRecord association isolation" do
    let(:shop_a) { create(:shop) }
    let(:shop_b) { create(:shop) }

    before do
      RlsContext.set!(shop_a.id)
      create(:customer, shop: shop_a, name: "Shop A Customer")
      RlsContext.set!(shop_b.id)
      create(:customer, shop: shop_b, name: "Shop B Customer")
    end

    it "shop_a.customers does not include shop_b data" do
      RlsContext.set!(shop_a.id)
      names = shop_a.customers.pluck(:name)
      expect(names).to include("Shop A Customer")
      expect(names).not_to include("Shop B Customer")
    end

    it "shop_b.customers does not include shop_a data" do
      RlsContext.set!(shop_b.id)
      names = shop_b.customers.pluck(:name)
      expect(names).to include("Shop B Customer")
      expect(names).not_to include("Shop A Customer")
    end
  end
end
