class FixRlsPolicyNullHandling < ActiveRecord::Migration[8.1]
  # The original policies used current_setting(...)::bigint directly.
  # When RlsContext.clear! sets app.current_shop_id to '' (empty string),
  # the cast to bigint raises "invalid input syntax for type bigint".
  # Fix: wrap in NULLIF so an empty string becomes NULL, which makes
  # shop_id = NULL → false for every row (blocks all rows, as intended).

  TENANT_TABLES_WITH_SHOP_ID = %w[customers orders events actions webhook_deduplications].freeze
  SUBQUERY_TABLES             = %w[approval_tokens execution_queue_items].freeze

  def up
    TENANT_TABLES_WITH_SHOP_ID.each do |table|
      execute "DROP POLICY IF EXISTS shop_isolation ON #{table}"
      execute <<~SQL
        CREATE POLICY shop_isolation ON #{table}
          USING (shop_id = NULLIF(current_setting('app.current_shop_id', TRUE), '')::bigint)
      SQL
    end

    execute "DROP POLICY IF EXISTS shop_isolation ON approval_tokens"
    execute <<~SQL
      CREATE POLICY shop_isolation ON approval_tokens
        USING (
          action_id IN (
            SELECT id FROM actions
            WHERE shop_id = NULLIF(current_setting('app.current_shop_id', TRUE), '')::bigint
          )
        )
    SQL

    execute "DROP POLICY IF EXISTS shop_isolation ON execution_queue_items"
    execute <<~SQL
      CREATE POLICY shop_isolation ON execution_queue_items
        USING (
          action_id IN (
            SELECT id FROM actions
            WHERE shop_id = NULLIF(current_setting('app.current_shop_id', TRUE), '')::bigint
          )
        )
    SQL
  end

  def down
    TENANT_TABLES_WITH_SHOP_ID.each do |table|
      execute "DROP POLICY IF EXISTS shop_isolation ON #{table}"
      execute <<~SQL
        CREATE POLICY shop_isolation ON #{table}
          USING (shop_id = current_setting('app.current_shop_id', TRUE)::bigint)
      SQL
    end

    execute "DROP POLICY IF EXISTS shop_isolation ON approval_tokens"
    execute <<~SQL
      CREATE POLICY shop_isolation ON approval_tokens
        USING (
          action_id IN (
            SELECT id FROM actions
            WHERE shop_id = current_setting('app.current_shop_id', TRUE)::bigint
          )
        )
    SQL

    execute "DROP POLICY IF EXISTS shop_isolation ON execution_queue_items"
    execute <<~SQL
      CREATE POLICY shop_isolation ON execution_queue_items
        USING (
          action_id IN (
            SELECT id FROM actions
            WHERE shop_id = current_setting('app.current_shop_id', TRUE)::bigint
          )
        )
    SQL
  end
end
