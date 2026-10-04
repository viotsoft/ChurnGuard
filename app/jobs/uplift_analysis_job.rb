# frozen_string_literal: true

require "csv"
require "json"
require "open3"
require "tmpdir"

class UpliftAnalysisJob < ApplicationJob
  queue_as :analysis

  discard_on ActiveJob::DeserializationError

  def perform(run_id)
    run = AnalysisRun.find(run_id)
    project = run.analysis_project
    run.update!(status: "running", started_at: Time.current, error_message: nil)

    Dir.mktmpdir("churnguard-uplift-") do |directory|
      orders_path = materialize(project.orders_file, directory, "orders.csv")
      experiment_path = materialize(project.experiment_file, directory, "experiment.csv") if project.experiment_file.attached?
      output_dir = File.join(directory, "output")
      FileUtils.mkdir_p(output_dir)
      config_path = File.join(directory, "config.json")
      File.write(config_path, JSON.pretty_generate(pipeline_config(project, run, orders_path, experiment_path, output_dir)))

      stdout, stderr, status = Open3.capture3(python_binary, pipeline_path.to_s, "--config", config_path)
      raise "Uplift pipeline failed: #{stderr.presence || stdout.presence || 'unknown error'}" unless status.success?

      persist_results!(run, project, output_dir)
    end
  rescue StandardError => e
    Rails.logger.error("[UpliftAnalysisJob] run=#{run_id} #{e.class}: #{e.message}")
    run&.update(status: "failed", error_message: e.message.to_s.first(2_000))
    project&.update(status: "failed", error_message: e.message.to_s.first(2_000))
  end

  private

  def materialize(attachment, directory, filename)
    path = File.join(directory, filename)
    attachment.blob.open { |file| FileUtils.cp(file.path, path) }
    path
  end

  def pipeline_config(project, run, orders_path, experiment_path, output_dir)
    {
      orders_path: orders_path,
      experiment_path: project.real_mode? ? experiment_path : nil,
      output_dir: output_dir,
      mapping: project.column_mapping,
      campaign_date: project.campaign_date&.iso8601,
      outcome_window_days: project.outcome_window_days,
      gross_margin_rate: project.gross_margin_rate.to_f,
      discount_rate: project.discount_rate.to_f,
      contact_cost: project.contact_cost.to_f,
      randomized_treatment: project.randomized_treatment,
      sample_dataset: project.data_audit["sample_dataset"] == true,
      seed: run.seed,
      hash_secret: ENV.fetch("DATA_LAB_HASH_SECRET", Rails.application.secret_key_base)
    }
  end

  def persist_results!(run, project, output_dir)
    summary = JSON.parse(File.read(File.join(output_dir, "summary.json")))
    predictions_path = File.join(output_dir, "predictions.csv")

    AnalysisRun.transaction do
      run.analysis_predictions.delete_all
      CSV.foreach(predictions_path, headers: true).first(100).each do |row|
        run.analysis_predictions.create!(
          rank: row.fetch("rank"),
          customer_key_hash: row.fetch("customer_key_hash"),
          customer_label: row.fetch("customer_label"),
          uplift_score: row.fetch("uplift_score"),
          probability_treatment: row.fetch("probability_treatment"),
          probability_control: row.fetch("probability_control"),
          average_order_value: row.fetch("average_order_value"),
          expected_incremental_revenue: row.fetch("expected_incremental_revenue"),
          expected_incremental_profit: row.fetch("expected_incremental_profit"),
          segment: row.fetch("segment"),
          recommended_action: row.fetch("recommended_action")
        )
      end

      run.update!(
        status: "completed",
        evidence_type: summary.fetch("evidence_type"),
        model_version: summary.fetch("model_version"),
        metrics: summary.fetch("metrics"),
        deciles: summary.fetch("deciles"),
        warnings: summary.fetch("warnings"),
        completed_at: Time.current
      )
      project.update!(
        status: "completed",
        data_audit: project.data_audit.deep_merge(summary.fetch("data_audit")),
        error_message: nil
      )
    end

    File.open(predictions_path, "rb") do |file|
      run.predictions_file.attach(
        io: file,
        filename: "#{project.name.parameterize}-uplift-predictions.csv",
        content_type: "text/csv"
      )
    end
  end

  def python_binary
    ENV.fetch("PYTHON_BIN", "python3")
  end

  def pipeline_path
    Rails.root.join("research/ml/uplift_lab_pipeline.py")
  end
end
