class AddUpliftFieldsToActions < ActiveRecord::Migration[8.1]
  def change
    add_column :actions, :treatment_key, :string
    add_column :actions, :uplift_score, :decimal, precision: 6, scale: 4
    add_column :actions, :expected_incremental_revenue, :decimal, precision: 10, scale: 2
    add_column :actions, :model_version, :string
    add_column :actions, :holdout, :boolean, null: false, default: false
    add_column :actions, :outcome_window_days, :integer

    add_index :actions, [:shop_id, :model_version]
    add_index :actions, [:shop_id, :treatment_key]
    add_index :actions, [:shop_id, :holdout]
  end
end
