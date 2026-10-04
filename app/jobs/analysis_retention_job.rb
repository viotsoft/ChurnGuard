# frozen_string_literal: true

class AnalysisRetentionJob < ApplicationJob
  queue_as :analysis

  def perform
    AnalysisProject.where("raw_expires_at <= ?", Time.current).find_each do |project|
      project.orders_file.purge if project.orders_file.attached?
      project.experiment_file.purge if project.experiment_file.attached?
    end

    AnalysisProject.where("results_expires_at <= ?", Time.current).find_each(&:destroy!)
    SandboxMagicLink.where("expires_at < ?", 24.hours.ago).delete_all
  end
end
