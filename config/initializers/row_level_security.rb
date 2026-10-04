# Postgres Row-Level Security — sets app.current_shop_id per database connection
#
# Every query on RLS-protected tables (customers, orders, events, actions, etc.)
# is automatically filtered to only rows belonging to the current shop.
#
# Usage:
#   RlsContext.set(shop_id) { ... }   # wraps a block
#   RlsContext.set!(shop_id)           # sets for the rest of the connection (Sidekiq jobs)
#
# The RLS policy in the DB: shop_id = current_setting('app.current_shop_id', TRUE)::bigint
# The TRUE flag makes current_setting return NULL (not raise) when unset —
# which means RLS blocks ALL rows when no shop_id is set. That's the safe default.

module RlsContext
  # Set shop_id for the duration of a block, then restore the previous value
  def self.set(shop_id)
    previous = current_shop_id
    set!(shop_id)
    yield
  ensure
    if previous
      set!(previous)
    else
      clear!
    end
  end

  # Set shop_id for the duration of the current DB connection (Sidekiq jobs, etc.)
  def self.set!(shop_id)
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(
        ["SELECT set_config('app.current_shop_id', ?, FALSE)", shop_id.to_s]
      )
    )
  end

  # Clear shop_id (makes RLS block all rows — the safe default)
  def self.clear!
    ActiveRecord::Base.connection.execute(
      "SELECT set_config('app.current_shop_id', '', FALSE)"
    )
  end

  def self.current_shop_id
    result = ActiveRecord::Base.connection.execute(
      "SELECT current_setting('app.current_shop_id', TRUE) AS shop_id"
    ).first
    id = result&.fetch("shop_id", nil)
    id.present? ? id.to_i : nil
  end
end
