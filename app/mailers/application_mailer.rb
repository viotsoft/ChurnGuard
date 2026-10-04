class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", ENV.fetch("APP_MAILER_FROM", "ChurnGuard <noreply@churnguard.local>"))
  layout "mailer"
end
