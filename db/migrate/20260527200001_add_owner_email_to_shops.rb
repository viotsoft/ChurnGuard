class AddOwnerEmailToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :owner_email, :string
  end
end
