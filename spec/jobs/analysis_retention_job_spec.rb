require "rails_helper"

RSpec.describe AnalysisRetentionJob, type: :job do
  it "purges expired raw CSV files but keeps current results" do
    project = create(:analysis_project, raw_expires_at: 1.hour.ago, results_expires_at: 2.days.from_now)
    path = Rails.root.join("spec/fixtures/files/data_lab/orders.csv")
    project.orders_file.attach(io: File.open(path, "rb"), filename: "orders.csv", content_type: "text/csv")

    described_class.perform_now

    expect(project.reload.orders_file).not_to be_attached
    expect(project).to be_persisted
  end

  it "deletes projects whose result retention has elapsed" do
    project = create(:analysis_project, raw_expires_at: 2.days.ago, results_expires_at: 1.minute.ago)

    expect { described_class.perform_now }.to change(AnalysisProject, :count).by(-1)
    expect(AnalysisProject.find_by(id: project.id)).to be_nil
  end
end
