# frozen_string_literal: true

require "digest"

class SandboxMagicLink < ApplicationRecord
  belongs_to :sandbox_user

  validates :token_digest, :expires_at, presence: true

  scope :active, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  def self.issue_for!(user:, request_ip: nil)
    raw_token = SecureRandom.urlsafe_base64(32)
    link = create!(
      sandbox_user: user,
      token_digest: digest(raw_token),
      expires_at: 15.minutes.from_now,
      request_ip: request_ip
    )
    [link, raw_token]
  end

  def self.authenticate(raw_token)
    return if raw_token.blank?

    active.find_by(token_digest: digest(raw_token))
  end

  def consume!
    update!(consumed_at: Time.current)
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end
end
