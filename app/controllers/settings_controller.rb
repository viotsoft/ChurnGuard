# SettingsController — shop preferences and Klaviyo integration management.
#
# Shows connection status for Klaviyo (API key present/missing) and lets the
# owner update their key. Phase 8 hardening will add key validation against
# the Klaviyo API before saving.
class SettingsController < AuthenticatedController
  layout "dashboard"

  def show
    @shop              = current_shop
    @klaviyo_connected = current_shop.klaviyo_api_key.present?
  end

  def update
    if current_shop.update(settings_params)
      redirect_to settings_path, notice: "Settings saved"
    else
      @shop              = current_shop
      @klaviyo_connected = current_shop.klaviyo_api_key.present?
      render :show, status: :unprocessable_content
    end
  end

  private

  def settings_params
    params.require(:shop).permit(:klaviyo_api_key)
  end
end
