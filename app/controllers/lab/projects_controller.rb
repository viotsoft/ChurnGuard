# frozen_string_literal: true

module Lab
  class ProjectsController < ApplicationController
    before_action :set_project, only: %i[show mapping update_mapping run status download download_source destroy]

    def index
      @projects = current_sandbox_user.analysis_projects.order(created_at: :desc)
    end

    def new
      @project = current_sandbox_user.analysis_projects.new
    end

    def create
      @project = current_sandbox_user.analysis_projects.new(project_create_params)
      @project.status = "uploaded"

      if @project.save
        inspect_uploads!(@project)
        redirect_to mapping_lab_project_path(@project), notice: "Files uploaded. Confirm the detected columns."
      else
        render :new, status: :unprocessable_entity
      end
    rescue CsvDatasetInspector::InvalidCsv => e
      @project&.destroy!
      @project = current_sandbox_user.analysis_projects.new(name: project_create_params[:name])
      @project.errors.add(:orders_file, e.message)
      render :new, status: :unprocessable_entity
    end

    def show
      @run = @project.latest_run
      @predictions = @run&.analysis_predictions&.order(:rank) || AnalysisPrediction.none
    end

    def mapping
      unless @project.orders_file.attached?
        redirect_to lab_project_path(@project), alert: "The source CSV has expired, so its mapping can no longer be changed."
        return
      end

      refresh_upload_audit! if @project.data_audit.dig("orders", "headers").blank?
      @orders_headers = @project.data_audit.dig("orders", "headers") || []
      @experiment_headers = @project.data_audit.dig("experiment", "headers") || []
    end

    def update_mapping
      mappings = normalized_mappings
      errors = CsvDatasetInspector.mapping_errors(
        mappings: mappings,
        experiment_attached: @project.experiment_file.attached? && selected_analysis_mode == "real",
        campaign_date: project_mapping_params[:campaign_date]
      )

      if errors.any?
        @project.errors.add(:base, errors.join(" "))
        mapping
        render :mapping, status: :unprocessable_entity
        return
      end

      @project.update!(
        column_mapping: mappings,
        campaign_date: project_mapping_params[:campaign_date].presence,
        outcome_window_days: project_mapping_params[:outcome_window_days],
        gross_margin_rate: percent_to_rate(project_mapping_params[:gross_margin_percent]),
        discount_rate: percent_to_rate(project_mapping_params[:discount_percent]),
        contact_cost: project_mapping_params[:contact_cost],
        randomized_treatment: project_mapping_params[:randomized_treatment] == "1",
        mode: selected_analysis_mode,
        status: "ready",
        error_message: nil
      )
      redirect_to lab_project_path(@project), notice: "Dataset configuration is ready."
    end

    def run
      if @project.status.in?(%w[running validating])
        redirect_to lab_project_path(@project), alert: "This project is already running."
        return
      end

      run = @project.analysis_runs.create!(status: "queued", seed: 42)
      @project.update!(status: "running", error_message: nil)
      UpliftAnalysisJob.perform_later(run.id)
      redirect_to lab_project_path(@project), notice: "Analysis started. This page will update automatically."
    end

    def status
      render json: {
        status: @project.status,
        run_status: @project.latest_run&.status,
        redirect_url: @project.status.in?(%w[completed failed]) ? lab_project_path(@project) : nil
      }
    end

    def download
      run = @project.latest_run
      unless run&.completed? && run.predictions_file.attached?
        redirect_to lab_project_path(@project), alert: "Predictions are not ready yet."
        return
      end

      redirect_to rails_blob_path(run.predictions_file, disposition: "attachment", only_path: true)
    end

    def download_source
      attachment = params[:kind] == "experiment" ? @project.experiment_file : @project.orders_file
      unless attachment.attached?
        redirect_to lab_project_path(@project), alert: "This source file has expired or is unavailable."
        return
      end

      redirect_to rails_blob_path(attachment, disposition: "attachment", only_path: true)
    end

    def sample
      project = SyntheticSampleGenerator.call(user: current_sandbox_user)
      inspect_uploads!(project)
      project.update!(data_audit: project.data_audit.merge("sample_dataset" => true))
      redirect_to mapping_lab_project_path(project), notice: "Sample project created. Confirm the columns, then run it."
    end

    def destroy
      @project.destroy!
      redirect_to lab_root_path, notice: "Project and its private files were deleted."
    end

    private

    def set_project
      @project = current_sandbox_user.analysis_projects.find(params[:id])
    end

    def project_create_params
      params.require(:analysis_project).permit(:name, :orders_file, :experiment_file)
    end

    def project_mapping_params
      params.require(:analysis_project).permit(
        :campaign_date, :outcome_window_days, :gross_margin_percent,
        :discount_percent, :contact_cost, :randomized_treatment, :analysis_mode,
        orders_mapping: CsvDatasetInspector::ORDER_FIELDS,
        experiment_mapping: CsvDatasetInspector::EXPERIMENT_FIELDS
      )
    end

    def normalized_mappings
      permitted = project_mapping_params
      {
        "orders" => normalized_mapping(permitted[:orders_mapping], CsvDatasetInspector::ORDER_FIELDS),
        "experiment" => normalized_mapping(permitted[:experiment_mapping], CsvDatasetInspector::EXPERIMENT_FIELDS)
      }
    end

    def normalized_mapping(mapping, allowed_fields)
      return {} if mapping.blank?

      parameters = mapping.respond_to?(:permit) ? mapping : ActionController::Parameters.new(mapping)
      parameters.permit(*allowed_fields).to_h.compact_blank
    end

    def inspect_uploads!(project)
      orders, experiment = inspect_project_attachments(project)

      project.update!(
        data_audit: { "orders" => orders.except("suggested_mapping"),
                      "experiment" => experiment&.except("suggested_mapping") }.compact,
        column_mapping: {
          "orders" => orders.fetch("suggested_mapping"),
          "experiment" => experiment&.fetch("suggested_mapping") || {}
        },
        mode: experiment ? "real" : "semi_synthetic",
        status: "mapping_required"
      )
    end

    def refresh_upload_audit!
      orders, experiment = inspect_project_attachments(@project)
      @project.update!(
        data_audit: @project.data_audit.merge(
          "orders" => orders.except("suggested_mapping"),
          "experiment" => experiment&.except("suggested_mapping")
        ).compact
      )
    end

    def inspect_project_attachments(project)
      orders = CsvDatasetInspector.inspect_attachment(project.orders_file, type: :orders)
      experiment = if project.experiment_file.attached?
                     CsvDatasetInspector.inspect_attachment(project.experiment_file, type: :experiment)
                   end
      [orders, experiment]
    end

    def percent_to_rate(value)
      value.to_d / 100
    end

    def selected_analysis_mode
      requested = project_mapping_params[:analysis_mode]
      return "semi_synthetic" unless @project.experiment_file.attached?

      AnalysisProject::MODES.include?(requested) ? requested : "real"
    end
  end
end
