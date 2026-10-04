# ApprovalsController — token-authenticated one-tap approval flow.
#
# No Shopify session required — the JWT in the query string IS the authentication.
# Owners click links from approval emails; this works without being logged in.
#
# Security model:
#   1. JWT signature verified (HS256, secret_key_base) — forged tokens rejected
#   2. ApprovalToken found by SHA-256 hash of the JWT — tampered tokens rejected
#   3. consumed_at enforced — token is single-use, replay rejected
#   4. expires_at enforced — 72-hour window, then expired
#   5. RLS context set from JWT payload (shop_id) — cross-shop access impossible
#
# Flow (approve):
#   JWT decode → set RLS(shop_id) → find token record → check consumed/expired
#   → token.consume! → action.approve! → enqueue KlaviyoExecutionJob → render approved
class ApprovalsController < ApplicationController
  layout "approval"


  # GET /approvals/approve?token=...
  # One-tap: validates token, marks action approved, queues Klaviyo campaign.
  def approve
    token_record = resolve_token
    return unless token_record  # rendered an error page already

    action = token_record.action
    token_record.consume!
    action.approve!

    KlaviyoExecutionJob.perform_later(action_id: action.id)

    @action   = action
    @customer = action.customer
    render :approved
  end

  # GET /approvals/skip?token=...
  # One-tap: validates token, marks action skipped.
  def skip
    token_record = resolve_token
    return unless token_record

    action = token_record.action
    token_record.consume!
    action.skip!

    @action   = action
    @customer = action.customer
    render :skipped
  end

  private

  # Validates the raw JWT from params[:token] and returns the ApprovalToken record,
  # or renders an error page and returns nil.
  #
  # Steps:
  #   1. Presence check (blank → invalid)
  #   2. JWT decode + signature verify → extracts shop_id for RLS context
  #   3. RLS context set so all subsequent AR queries are scoped to the right shop
  #   4. Token lookup by hash (constant-time)
  #   5. consumed? → already_used page
  #   6. expired? → expired page
  def resolve_token
    raw_jwt = params[:token]

    if raw_jwt.blank?
      render :invalid, status: :bad_request
      return nil
    end

    # Step 1 — verify JWT signature and extract payload
    payload = ApprovalToken.decode!(raw_jwt)

    # Step 2 — set RLS context so AR queries see the right shop's rows
    shop_id = payload[:shop_id]
    unless shop_id.present?
      render :invalid, status: :unprocessable_content
      return nil
    end
    RlsContext.set!(shop_id)

    # Step 3 — look up the token record (hash-based, no timing leak)
    token_record = ApprovalToken.find_by_jwt(raw_jwt)
    if token_record.nil?
      render :invalid, status: :not_found
      return nil
    end

    # Step 4 — single-use check
    if token_record.consumed?
      @action           = token_record.action
      @customer         = @action.customer
      @previously_approved = @action.status == "approved"
      render :already_used
      return nil
    end

    # Step 5 — window check (DB-level; JWT exp is the second layer)
    if token_record.expired?
      @action           = token_record.action
      @customer         = @action.customer
      @expired_days_ago = [(Time.current - token_record.expires_at) / 1.day, 1].max.ceil
      render :expired
      return nil
    end

    token_record

  rescue JWT::DecodeError
    # Covers expired JWT (exp in past), bad signature, malformed token
    render :invalid, status: :unauthorized
    nil
  end
end
