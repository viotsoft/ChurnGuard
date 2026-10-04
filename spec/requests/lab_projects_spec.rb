require "rails_helper"

RSpec.describe "Data Lab projects", type: :request do
  let(:user) { create(:sandbox_user) }

  before do
    _link, token = SandboxMagicLink.issue_for!(user: user)
    get lab_session_path, params: { token: token }
  end

  it "renders the new project upload form with the public lab route" do
    get new_lab_project_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Upload e-commerce data")
    expect(response.body).to include(%(action="#{lab_projects_path}"))
  end

  it "isolates projects owned by another sandbox user" do
    other_project = create(:analysis_project, sandbox_user: create(:sandbox_user))

    get lab_project_path(other_project)

    expect(response).to have_http_status(:not_found)
  end

  it "uploads orders and an experiment without creating Shopify records" do
    orders = fixture_file_upload(Rails.root.join("spec/fixtures/files/data_lab/orders.csv"), "text/csv")
    experiment = fixture_file_upload(Rails.root.join("spec/fixtures/files/data_lab/experiment.csv"), "text/csv")
    customer_count = Customer.count
    order_count = Order.count
    action_count = Action.count

    expect do
      post lab_projects_path, params: {
        analysis_project: { name: "Pilot", orders_file: orders, experiment_file: experiment }
      }
    end.to change(user.analysis_projects, :count).by(1)

    expect(Customer.count).to eq(customer_count)
    expect(Order.count).to eq(order_count)
    expect(Action.count).to eq(action_count)

    project = user.analysis_projects.last
    expect(response).to redirect_to(mapping_lab_project_path(project))
    expect(project.status).to eq("mapping_required")
    expect(project.column_mapping.dig("orders", "amount")).to eq("amount")
  end

  it "queues analysis without creating an executable Action" do
    project = create(:analysis_project, sandbox_user: user)
    action_count = Action.count

    expect do
      post run_lab_project_path(project)
    end.to have_enqueued_job(UpliftAnalysisJob)

    expect(Action.count).to eq(action_count)
    expect(project.reload.status).to eq("running")
  end

  it "marks the built-in dataset as synthetic proof" do
    post sample_lab_projects_path

    project = user.analysis_projects.last
    expect(project.data_audit["sample_dataset"]).to be(true)
    expect(project.orders_file).to be_attached
    expect(project.experiment_file).to be_attached
  end

  it "allows simulation mode without experiment mappings when an experiment file is attached" do
    orders = fixture_file_upload(Rails.root.join("spec/fixtures/files/data_lab/orders.csv"), "text/csv")
    experiment = fixture_file_upload(Rails.root.join("spec/fixtures/files/data_lab/experiment.csv"), "text/csv")
    post lab_projects_path, params: {
      analysis_project: { name: "Simulation fallback", orders_file: orders, experiment_file: experiment }
    }
    project = user.analysis_projects.last

    patch mapping_lab_project_path(project), params: {
      analysis_project: {
        analysis_mode: "semi_synthetic",
        outcome_window_days: 30,
        gross_margin_percent: 40,
        discount_percent: 10,
        contact_cost: 0.05,
        orders_mapping: {
          customer_id: "customer_id",
          order_id: "order_id",
          ordered_at: "ordered_at",
          amount: "amount"
        },
        experiment_mapping: {}
      }
    }

    expect(response).to redirect_to(lab_project_path(project))
    expect(project.reload).to have_attributes(mode: "semi_synthetic", status: "ready")
  end

  it "rebuilds upload preview metadata without losing completed audit metrics" do
    project = create(
      :analysis_project,
      sandbox_user: user,
      status: "completed",
      data_audit: { "valid_orders" => 4 },
      column_mapping: { "orders" => CsvDatasetInspector::REQUIRED_ORDER_FIELDS.index_with(&:itself) }
    )
    orders = fixture_file_upload(Rails.root.join("spec/fixtures/files/data_lab/orders.csv"), "text/csv")
    project.orders_file.attach(orders)

    get mapping_lab_project_path(project)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("c-001")
    expect(project.reload.data_audit).to include("valid_orders" => 4)
    expect(project.data_audit.dig("orders", "headers")).to include("customer_id", "amount")
  end
end
