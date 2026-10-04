require "digest"
require "jwt"

# ApprovalToken — single-use JWT nonce stored as a SHA-256 hash.
#
# Security model:
#   - Raw JWT is signed with HS256 using Rails.application.secret_key_base.
#   - Only the SHA-256 hash of the JWT is stored in the DB — raw tokens are
#     never persisted, so a DB breach cannot reveal usable approval links.
#   - Tokens expire after 72 hours (exp claim + expires_at column, both enforced).
#   - consumed_at is set on first use, making tokens single-use (prevents replay).
#
# Payload: { action_id:, shop_id:, exp: unix_timestamp }
class ApprovalToken < ApplicationRecord
  belongs_to :action

  JWT_ALGORITHM = "HS256"
  TOKEN_TTL     = 72.hours

  validates :token_hash, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :valid,   -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at < ?", Time.current) }

  # ── Generation ──────────────────────────────────────────────────────────────

  # Generates a signed JWT for the given action, persists the hash, and returns
  # the raw JWT string for embedding in the approval email.
  def self.generate_for!(action:)
    expires_at = TOKEN_TTL.from_now

    payload = {
      action_id: action.id,
      shop_id:   action.shop_id,
      exp:       expires_at.to_i
    }

    raw_jwt    = JWT.encode(payload, jwt_secret, JWT_ALGORITHM)
    token_hash = Digest::SHA256.hexdigest(raw_jwt)

    create!(action: action, token_hash: token_hash, expires_at: expires_at)

    raw_jwt
  end

  # Decodes and verifies a raw JWT. Returns the payload hash or raises JWT::DecodeError.
  def self.decode!(raw_jwt)
    payload, _header = JWT.decode(raw_jwt, jwt_secret, true, algorithms: [JWT_ALGORITHM])
    payload.symbolize_keys
  end

  # ── Lookup ──────────────────────────────────────────────────────────────────

  # Find a token record by the raw JWT (hashed for constant-time lookup).
  def self.find_by_jwt(raw_jwt)
    find_by(token_hash: Digest::SHA256.hexdigest(raw_jwt))
  end

  # ── Instance ────────────────────────────────────────────────────────────────

  def consumed?
    consumed_at.present?
  end

  def expired?
    expires_at < Time.current
  end

  def valid_for_use?
    !consumed? && !expired?
  end

  # Marks this token as consumed (single-use enforcement).
  def consume!
    update!(consumed_at: Time.current)
  end

  private_class_method def self.jwt_secret
    Rails.application.secret_key_base
  end
end
