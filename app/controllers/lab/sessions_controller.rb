# frozen_string_literal: true

module Lab
  class SessionsController < ::ApplicationController
    layout "lab"
    helper_method :current_sandbox_user

    rate_limit to: 5, within: 1.hour, only: :create,
               by: -> { request.remote_ip },
               with: -> { redirect_to lab_sign_in_path, alert: "Too many sign-in requests. Try again later." }

    def new
      redirect_to lab_root_path if current_sandbox_user
    end

    def create
      email = params[:email].to_s.strip.downcase
      user = SandboxUser.find_or_initialize_by(email: email)

      if user.save
        _link, raw_token = SandboxMagicLink.issue_for!(user: user, request_ip: request.remote_ip)
        LabMagicLinkMailer.sign_in(user: user, raw_token: raw_token).deliver_later
        flash[:notice] = "Check your email for a private sign-in link."
        flash[:development_magic_link] = lab_session_url(token: raw_token) if Rails.env.development?
        redirect_to lab_sign_in_path
      else
        flash.now[:alert] = "Enter a valid email address."
        render :new, status: :unprocessable_entity
      end
    end

    def show
      magic_link = SandboxMagicLink.authenticate(params[:token])
      unless magic_link
        redirect_to lab_sign_in_path, alert: "This sign-in link is invalid or has expired."
        return
      end

      magic_link.consume!
      reset_session
      session[:sandbox_user_id] = magic_link.sandbox_user_id
      magic_link.sandbox_user.update!(last_signed_in_at: Time.current)
      redirect_to lab_root_path, notice: "Signed in to Data Lab."
    end

    def destroy
      reset_session
      redirect_to lab_sign_in_path, notice: "Signed out."
    end

    private

    def current_sandbox_user
      SandboxUser.find_by(id: session[:sandbox_user_id])
    end
  end
end
