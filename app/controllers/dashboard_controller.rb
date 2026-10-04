# DashboardController — primary owner-facing interface.
#
# Layout: "dashboard" (no sidebar on index, left-nav on history/insights).
# All actions require Shopify OAuth via AuthenticatedController.
# RLS context is set by AuthenticatedController#set_rls_context before each action.
#
# Index (home screen):
#   Portrait-oriented approval queue, max-width 560px cards, NO charts.
#   Design rule (DESIGN.md): charts live ONLY in insights, never on the home screen.
class DashboardController < AuthenticatedController
  layout "dashboard"

  # GET / — primary approval queue (the home screen)
  # Cards: Fraunces customer name, Geist Mono revenue at risk (shown first),
  # terracotta approve CTA, ghost skip button. Card flip animation on approve.
  def index
    @pending_actions = current_shop.actions
                                   .pending
                                   .includes(customer: :orders)
                                   .order(created_at: :desc)
    @pending_count   = @pending_actions.size
    @metrics         = monthly_metrics
  end

  # GET /dashboard/history — action history table
  # Shows all non-pending actions: approved, skipped, expired, failed, executed.
  def history
    @actions = current_shop.actions
                           .where.not(status: "pending")
                           .includes(:customer)
                           .order(updated_at: :desc)
                           .limit(100)
  end

  # GET /dashboard/insights — retention metrics (ONLY place charts are allowed)
  def insights
    @metrics     = monthly_metrics
    @all_metrics = lifetime_metrics
  end

  # GET /dashboard/demo_results — pitch-friendly demo proof.
  # This is a secondary screen, so metrics can be shown here. The approval queue
  # remains chart-free per DESIGN.md.
  def demo_results
    @demo_metrics = demo_metrics
    @risk_breakdown = current_shop.customers.group(:risk_tier).count
    @top_pending_actions = current_shop.actions
                                      .pending
                                      .includes(:customer)
                                      .order(revenue_at_risk: :desc)
                                      .limit(5)
  end

  private

  def monthly_metrics
    since = Time.current.beginning_of_month
    executed_this_month = current_shop.actions
                                      .executed
                                      .where("executed_at >= ?", since)
    {
      actions_sent:       executed_this_month.count,
      customers_retained: executed_this_month.count,
      revenue_saved:      executed_this_month.sum(:revenue_at_risk).to_f
    }
  end

  def lifetime_metrics
    executed = current_shop.actions.executed
    {
      total_sent:      executed.count,
      total_retained:  executed.count,
      total_revenue:   executed.sum(:revenue_at_risk).to_f,
      pending_count:   current_shop.actions.pending.count,
      skipped_count:   current_shop.actions.skipped.count,
      expired_count:   current_shop.actions.expired.count,
      failed_count:    current_shop.actions.failed.count
    }
  end

  def demo_metrics
    pending = current_shop.actions.pending
    executed = current_shop.actions.executed
    {
      customers_scored:        current_shop.customers.where.not(risk_tier: nil).count,
      total_customers:         current_shop.customers.count,
      orders_synced:           current_shop.orders.paid.count,
      pending_actions:         pending.count,
      pending_revenue_at_risk: pending.sum(:revenue_at_risk).to_f,
      executed_actions:        executed.count,
      estimated_recovered:     executed.sum(:revenue_at_risk).to_f,
      skipped_actions:         current_shop.actions.skipped.count,
      uplift_actions:          current_shop.actions.uplift_v3.count,
      expected_incremental:    current_shop.actions.uplift_v3.sum(:expected_incremental_revenue).to_f,
      average_uplift:          average_uplift_score
    }
  end

  def average_uplift_score
    actions = current_shop.actions.uplift_v3.where.not(uplift_score: nil)
    return 0.0 if actions.empty?

    actions.average(:uplift_score).to_f
  end
end
