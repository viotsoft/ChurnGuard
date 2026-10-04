# frozen_string_literal: true

class AnalysisProject < ApplicationRecord
  MAX_UPLOAD_SIZE = 200.megabytes
  STATUSES = %w[uploaded mapping_required validating ready running completed failed expired].freeze
  MODES = %w[real semi_synthetic].freeze

  belongs_to :sandbox_user
  has_many :analysis_runs, dependent: :destroy
  has_one_attached :orders_file
  has_one_attached :experiment_file

  validates :name, presence: true, length: { maximum: 100 }
  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }, allow_nil: true
  validates :outcome_window_days, inclusion: { in: 7..90 }
  validates :gross_margin_rate, :discount_rate,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :contact_cost, numericality: { greater_than_or_equal_to: 0 }
  validate :acceptable_uploads

  before_validation :set_expirations, on: :create

  def latest_run
    analysis_runs.order(created_at: :desc).first
  end

  def real_mode?
    mode == "real"
  end

  private

  def set_expirations
    self.raw_expires_at ||= 24.hours.from_now
    self.results_expires_at ||= 30.days.from_now
  end

  def acceptable_uploads
    [orders_file, experiment_file].each do |attachment|
      next unless attachment.attached?

      errors.add(attachment.name, "must be a CSV file") unless csv_attachment?(attachment)
      errors.add(attachment.name, "must be 200 MB or smaller") if attachment.blob.byte_size > MAX_UPLOAD_SIZE
    end
  end

  def csv_attachment?(attachment)
    attachment.blob.content_type.in?(%w[text/csv application/csv application/vnd.ms-excel text/plain]) ||
      attachment.filename.extension.downcase == ".csv"
  end
end
