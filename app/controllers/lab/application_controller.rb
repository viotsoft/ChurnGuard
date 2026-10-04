# frozen_string_literal: true

module Lab
  class ApplicationController < ::ApplicationController
    layout "lab"

    before_action :require_sandbox_user
    helper_method :current_sandbox_user

    private

    def current_sandbox_user
      @current_sandbox_user ||= SandboxUser.find_by(id: session[:sandbox_user_id])
    end

    def require_sandbox_user
      return if current_sandbox_user

      redirect_to lab_sign_in_path, alert: "Sign in to open Data Lab."
    end
  end
end
