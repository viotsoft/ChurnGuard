# frozen_string_literal: true

class AnalysisRun < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze
  EVIDENCE_TYPES = %w[experimental observational semi_synthetic].freeze

  belongs_to :analysis_project
  has_many :analysis_predictions, dependent: :destroy
  has_one_attached :predictions_file

  validates :status, inclusion: { in: STATUSES }
  validates :evidence_type, inclusion: { in: EVIDENCE_TYPES }, allow_nil: true

  def completed?
    status == "completed"
  end
end
