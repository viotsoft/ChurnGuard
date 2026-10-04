# frozen_string_literal: true

class LabMagicLinkMailer < ApplicationMailer
  def sign_in(user:, raw_token:)
    @user = user
    @sign_in_url = lab_session_url(token: raw_token)
    mail(to: user.email, subject: "Your ChurnGuard Data Lab sign-in link")
  end
end
