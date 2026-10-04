# frozen_string_literal: true

require "csv"
require "tempfile"

class SyntheticSampleGenerator
  CUSTOMER_COUNT = 10_000
  CAMPAIGN_DATE = Date.new(2026, 1, 1)

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
    @random = Random.new(42)
  end

  def call
    project = @user.analysis_projects.create!(
      name: "Sample retention experiment",
      status: "uploaded",
      mode: "real",
      campaign_date: CAMPAIGN_DATE,
      randomized_treatment: true
    )

    orders = Tempfile.new(["sample-orders", ".csv"])
    experiment = Tempfile.new(["sample-experiment", ".csv"])
    write_sample(orders, experiment)
    orders.rewind
    experiment.rewind
    project.orders_file.attach(io: orders, filename: "sample_orders.csv", content_type: "text/csv")
    project.experiment_file.attach(io: experiment, filename: "sample_experiment.csv", content_type: "text/csv")
    project
  ensure
    orders&.close!
    experiment&.close!
  end

  private

  def write_sample(orders_file, experiment_file)
    orders_csv = CSV.new(orders_file)
    experiment_csv = CSV.new(experiment_file)
    orders_csv << %w[customer_id order_id ordered_at amount currency status]
    experiment_csv << %w[customer_id treatment outcome assigned_at outcome_value treatment_key]

    CUSTOMER_COUNT.times do |index|
      customer_id = format("sample-%05d", index + 1)
      frequency = 1 + @random.rand(8)
      recency_days = 5 + @random.rand(330)
      average_value = 28 + @random.rand * 145
      write_orders(orders_csv, customer_id, index, frequency, recency_days, average_value)

      treatment = @random.rand < 0.5 ? 1 : 0
      base = [[0.06 + frequency * 0.012 - recency_days * 0.00012, 0.03].max, 0.42].min
      effect = index % 10 < 4 ? 0.10 : (index % 10 == 9 ? -0.05 : 0.015)
      probability = [[base + treatment * effect, 0.01].max, 0.85].min
      outcome = @random.rand < probability ? 1 : 0
      outcome_value = outcome == 1 ? (average_value * (0.75 + @random.rand * 0.6)).round(2) : 0
      experiment_csv << [customer_id, treatment, outcome, CAMPAIGN_DATE.iso8601, outcome_value, "retention_message"]
    end
  end

  def write_orders(csv, customer_id, customer_index, frequency, recency_days, average_value)
    frequency.times do |order_index|
      spacing = order_index * (20 + @random.rand(55))
      date = CAMPAIGN_DATE - recency_days - spacing
      amount = (average_value * (0.65 + @random.rand * 0.8)).round(2)
      csv << [customer_id, "sample-order-#{customer_index + 1}-#{order_index + 1}", date.iso8601, amount, "EUR", "paid"]
    end
  end
end
