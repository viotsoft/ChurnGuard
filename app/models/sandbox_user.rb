# frozen_string_literal: true

class SandboxUser < ApplicationRecord
  has_many :sandbox_magic_links, dependent: :destroy
  has_many :analysis_projects, dependent: :destroy

  before_validation :normalize_email

  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { case_sensitive: false }

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
