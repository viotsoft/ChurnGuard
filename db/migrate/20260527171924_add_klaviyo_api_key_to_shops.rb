class AddKlaviyoApiKeyToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :klaviyo_api_key, :string
  end
end
