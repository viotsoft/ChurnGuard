require "rails_helper"

RSpec.describe CsvDatasetInspector do
  def project_attachment(name, slot: :orders_file)
    project = create(:analysis_project)
    path = Rails.root.join("spec/fixtures/files/data_lab", name)
    project.public_send(slot).attach(io: File.open(path, "rb"), filename: name, content_type: "text/csv")
    project.public_send(slot)
  end

  it "detects canonical order columns" do
    result = described_class.inspect_attachment(project_attachment("orders.csv"), type: :orders)

    expect(result["suggested_mapping"]).to include(
      "customer_id" => "customer_id",
      "order_id" => "order_id",
      "ordered_at" => "ordered_at",
      "amount" => "amount"
    )
  end

  it "detects semicolon-delimited X5-style aliases" do
    result = described_class.inspect_attachment(project_attachment("x5_aliases.csv"), type: :orders)

    expect(result["delimiter"]).to eq(";")
    expect(result["suggested_mapping"]).to include(
      "customer_id" => "client_id",
      "order_id" => "transaction_id",
      "ordered_at" => "transaction_datetime",
      "amount" => "purchase_sum"
    )
  end

  it "excludes email and phone values from headers and the persisted preview" do
    result = described_class.inspect_attachment(project_attachment("orders_with_contact.csv"), type: :orders)

    expect(result["headers"]).not_to include("email", "phone_number")
    expect(result["ignored_headers"]).to contain_exactly("email", "phone_number")
    expect(result["preview"].to_json).not_to include("owner@example.test", "+10000000000")
  end

  it "requires campaign timing for a mapped experiment" do
    errors = described_class.mapping_errors(
      mappings: {
        "orders" => CsvDatasetInspector::REQUIRED_ORDER_FIELDS.index_with(&:itself),
        "experiment" => CsvDatasetInspector::REQUIRED_EXPERIMENT_FIELDS.index_with(&:itself)
      },
      experiment_attached: true,
      campaign_date: nil
    )

    expect(errors.join).to include("campaign date")
  end
end
