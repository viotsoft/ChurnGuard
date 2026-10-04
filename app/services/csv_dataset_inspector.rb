# frozen_string_literal: true

require "csv"

class CsvDatasetInspector
  class InvalidCsv < StandardError; end

  ORDER_FIELDS = %w[customer_id order_id ordered_at amount currency status customer_name].freeze
  EXPERIMENT_FIELDS = %w[customer_id treatment outcome assigned_at outcome_value treatment_key].freeze
  REQUIRED_ORDER_FIELDS = %w[customer_id order_id ordered_at amount].freeze
  REQUIRED_EXPERIMENT_FIELDS = %w[customer_id treatment outcome].freeze
  PRIVATE_CONTACT_FIELDS = %w[
    email e_mail email_address customer_email phone phone_number telephone mobile mobile_phone
  ].freeze
  ALIASES = {
    "customer_id" => %w[customer_id customerid client_id clientid shopify_customer_id cardholder],
    "order_id" => %w[order_id orderid invoice invoice_id invoiceid transaction_id receipt_id],
    "ordered_at" => %w[ordered_at order_date order_datetime invoicedate transaction_datetime date timestamp],
    "amount" => %w[amount total order_total revenue purchase_sum transaction_sum monetary],
    "currency" => %w[currency currency_code],
    "status" => %w[status order_status],
    "customer_name" => %w[customer_name name display_name],
    "treatment" => %w[treatment treatment_flg treatment_flag group segment exposed],
    "outcome" => %w[outcome target conversion converted response purchased],
    "assigned_at" => %w[assigned_at treatment_at campaign_date send_date],
    "outcome_value" => %w[outcome_value spend post_spend target_value],
    "treatment_key" => %w[treatment_key action campaign campaign_type]
  }.freeze

  def self.inspect_attachment(attachment, type:)
    raise InvalidCsv, "Select an orders CSV file." unless attachment.attached?

    attachment.blob.open do |file|
      sample_text = file.read(64.kilobytes).to_s.encode("UTF-8", invalid: :replace, undef: :replace).delete_prefix("\uFEFF")
      delimiter = detect_delimiter(sample_text)
      table = CSV.parse(sample_text, headers: true, col_sep: delimiter, liberal_parsing: true)
      source_headers = table.headers.to_a.compact.map(&:strip)
      raise InvalidCsv, "The CSV must contain a header row." if source_headers.empty?
      raise InvalidCsv, "Duplicate column names are not supported." if source_headers.uniq.size != source_headers.size

      ignored_headers = source_headers.select { |header| private_contact_field?(header) }
      headers = source_headers - ignored_headers

      fields = type.to_sym == :orders ? ORDER_FIELDS : EXPERIMENT_FIELDS
      {
        "headers" => headers,
        "ignored_headers" => ignored_headers,
        "delimiter" => delimiter,
        "preview" => table.first(8).map do |row|
          row.to_h.slice(*headers).transform_values { |value| value.to_s.first(120) }
        end,
        "suggested_mapping" => suggest_mapping(headers, fields)
      }
    end
  rescue CSV::MalformedCSVError, EncodingError => e
    raise InvalidCsv, "Could not read CSV: #{e.message}"
  end

  def self.mapping_errors(mappings:, experiment_attached:, campaign_date:)
    errors = []
    missing_orders = REQUIRED_ORDER_FIELDS - mappings.fetch("orders", {}).keys
    errors << "Map required order fields: #{missing_orders.join(', ')}." if missing_orders.any?

    if experiment_attached
      experiment = mappings.fetch("experiment", {})
      missing_experiment = REQUIRED_EXPERIMENT_FIELDS - experiment.keys
      errors << "Map required experiment fields: #{missing_experiment.join(', ')}." if missing_experiment.any?
      errors << "Provide a campaign date or map assigned_at." if experiment["assigned_at"].blank? && campaign_date.blank?
    end
    errors
  end

  def self.detect_delimiter(text)
    first_line = text.lines.first.to_s
    first_line.count(";") > first_line.count(",") ? ";" : ","
  end

  def self.suggest_mapping(headers, fields)
    normalized = headers.index_by { |header| normalize(header) }
    fields.each_with_object({}) do |field, mapping|
      alias_name = ALIASES.fetch(field, [field]).find { |candidate| normalized.key?(normalize(candidate)) }
      mapping[field] = normalized[normalize(alias_name)] if alias_name
    end
  end

  def self.normalize(value)
    value.to_s.downcase.strip.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")
  end

  def self.private_contact_field?(header)
    PRIVATE_CONTACT_FIELDS.include?(normalize(header))
  end
end
