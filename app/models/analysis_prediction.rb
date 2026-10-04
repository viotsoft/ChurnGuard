# frozen_string_literal: true

class AnalysisPrediction < ApplicationRecord
  belongs_to :analysis_run

  validates :rank, numericality: { greater_than: 0 }
  validates :customer_key_hash, :customer_label, :segment, :recommended_action, presence: true
  validates :uplift_score, :probability_treatment, :probability_control,
            numericality: { greater_than_or_equal_to: -1, less_than_or_equal_to: 1 }
end
