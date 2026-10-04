# frozen_string_literal: true

class CreateDataLab < ActiveRecord::Migration[8.1]
  def change
    create_table :sandbox_users do |t|
      t.string :email, null: false
      t.datetime :last_signed_in_at
      t.timestamps
      t.index "lower(email)", unique: true, name: :index_sandbox_users_on_lower_email
    end

    create_table :sandbox_magic_links do |t|
      t.references :sandbox_user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.string :request_ip
      t.timestamps
      t.index :token_digest, unique: true
      t.index :expires_at
    end

    create_table :analysis_projects do |t|
      t.references :sandbox_user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :status, null: false, default: "uploaded"
      t.string :mode
      t.jsonb :column_mapping, null: false, default: {}
      t.jsonb :data_audit, null: false, default: {}
      t.date :campaign_date
      t.integer :outcome_window_days, null: false, default: 30
      t.decimal :gross_margin_rate, precision: 6, scale: 4, null: false, default: 0.4
      t.decimal :discount_rate, precision: 6, scale: 4, null: false, default: 0.1
      t.decimal :contact_cost, precision: 10, scale: 2, null: false, default: 0
      t.boolean :randomized_treatment, null: false, default: false
      t.text :error_message
      t.datetime :raw_expires_at, null: false
      t.datetime :results_expires_at, null: false
      t.timestamps
      t.index %i[sandbox_user_id created_at]
      t.index :status
      t.index :raw_expires_at
      t.index :results_expires_at
    end

    create_table :analysis_runs do |t|
      t.references :analysis_project, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.string :evidence_type
      t.string :model_version
      t.integer :seed, null: false, default: 42
      t.jsonb :metrics, null: false, default: {}
      t.jsonb :deciles, null: false, default: []
      t.jsonb :warnings, null: false, default: []
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
      t.index %i[analysis_project_id created_at]
      t.index :status
    end

    create_table :analysis_predictions do |t|
      t.references :analysis_run, null: false, foreign_key: true
      t.integer :rank, null: false
      t.string :customer_key_hash, null: false
      t.string :customer_label, null: false
      t.decimal :uplift_score, precision: 8, scale: 6, null: false
      t.decimal :probability_treatment, precision: 8, scale: 6, null: false
      t.decimal :probability_control, precision: 8, scale: 6, null: false
      t.decimal :average_order_value, precision: 12, scale: 2, null: false, default: 0
      t.decimal :expected_incremental_revenue, precision: 12, scale: 2, null: false, default: 0
      t.decimal :expected_incremental_profit, precision: 12, scale: 2, null: false, default: 0
      t.string :segment, null: false
      t.string :recommended_action, null: false
      t.timestamps
      t.index %i[analysis_run_id rank], unique: true
    end
  end
end
