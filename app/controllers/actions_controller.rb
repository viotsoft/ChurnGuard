# ActionsController — dashboard-level approve/skip for shop owners.
#
# This is the Shopify-OAuth authenticated path. The shop owner is already
# logged in, so no ApprovalToken JWT is needed — Shopify session IS the auth.
#
# Contrast with ApprovalsController (token-authenticated, no login required),
# which handles the same approve/skip flow triggered from email links.
#
# On success the card is replaced via Turbo Stream so the queue updates
# in-place without a full page reload (enabling the CSS flip animation).
class ActionsController < AuthenticatedController
  before_action :load_action

  # PATCH /actions/:id/approve
  # Marks the action approved and enqueues Klaviyo execution.
  def approve
    @action.approve!
    KlaviyoExecutionJob.perform_later(action_id: @action.id)

    respond_to do |format|
      format.html do
        redirect_to dashboard_index_path,
          notice: "Discount queued for #{@action.customer.display_name} ✓"
      end
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            "action_#{@action.id}",
            partial: "dashboard/action_done",
            locals: { action: @action, outcome: :approved }
          ),
          turbo_stream.replace("pending-pill", partial: "dashboard/pending_pill",
            locals: { pending_count: current_shop.actions.pending.count })
        ]
      end
    end
  end

  # PATCH /actions/:id/skip
  # Marks the action skipped. No Klaviyo job.
  def skip
    @action.skip!

    respond_to do |format|
      format.html do
        redirect_to dashboard_index_path,
          notice: "Action skipped for #{@action.customer.display_name}"
      end
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            "action_#{@action.id}",
            partial: "dashboard/action_done",
            locals: { action: @action, outcome: :skipped }
          ),
          turbo_stream.replace("pending-pill", partial: "dashboard/pending_pill",
            locals: { pending_count: current_shop.actions.pending.count })
        ]
      end
    end
  end

  private

  def load_action
    @action = current_shop.actions.find(params[:id])
  end
end
