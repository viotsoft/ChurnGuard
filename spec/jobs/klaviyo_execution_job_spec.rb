require "rails_helper"

RSpec.describe KlaviyoExecutionJob, type: :job do
  let(:shop)     { create(:shop, klaviyo_api_key: "pk_test_abc123") }
  let(:customer) { create(:customer, shop: shop, email: "maria@example.com") }
  let(:action) do
    create(:action, shop: shop, customer: customer,
           status: "approved", proposed_discount: "15%",
           risk_tier: "high", revenue_at_risk: 89.0,
           expires_at: 72.hours.from_now)
  end

  before { RlsContext.set!(shop.id) }

  # ── Job configuration ────────────────────────────────────────────────────────

  it "is queued on the execution queue" do
    expect(described_class.queue_name).to eq("execution")
  end

  it "has 5 max retries configured" do
    expect(described_class.sidekiq_options_hash["retry"]).to eq(5)
  end

  # ── Happy path ───────────────────────────────────────────────────────────────

  describe "#perform" do
    context "when Klaviyo succeeds" do
      before do
        stub_request(:post, "https://a.klaviyo.com/api/events/")
          .to_return(status: 202, body: "", headers: {})
      end

      it "calls the Klaviyo Events API" do
        described_class.new.perform(action_id: action.id)
        expect(WebMock).to have_requested(:post, "https://a.klaviyo.com/api/events/")
      end

      it "marks the action as executed" do
        described_class.new.perform(action_id: action.id)
        expect(action.reload.status).to eq("executed")
      end

      it "stamps executed_at on the action" do
        described_class.new.perform(action_id: action.id)
        expect(action.reload.executed_at).to be_within(5.seconds).of(Time.current)
      end
    end

    # ── Missing action ───────────────────────────────────────────────────────

    context "when the action does not exist" do
      it "returns early without raising" do
        expect { described_class.new.perform(action_id: 999_999) }.not_to raise_error
      end

      it "does not call the Klaviyo API" do
        stub_request(:post, "https://a.klaviyo.com/api/events/")
        described_class.new.perform(action_id: 999_999)
        expect(WebMock).not_to have_requested(:post, "https://a.klaviyo.com/api/events/")
      end
    end

    # ── Missing API key ──────────────────────────────────────────────────────

    context "when the shop has no Klaviyo API key" do
      before { shop.update_columns(klaviyo_api_key: nil) }

      it "returns early without raising" do
        expect { described_class.new.perform(action_id: action.id) }.not_to raise_error
      end

      it "does not call the Klaviyo API" do
        stub_request(:post, "https://a.klaviyo.com/api/events/")
        described_class.new.perform(action_id: action.id)
        expect(WebMock).not_to have_requested(:post, "https://a.klaviyo.com/api/events/")
      end

      it "does not mark the action as executed" do
        described_class.new.perform(action_id: action.id)
        expect(action.reload.status).not_to eq("executed")
      end
    end

    # ── Rate limit (HTTP 429) ─────────────────────────────────────────────────

    context "when Klaviyo returns 429 (rate limit)" do
      before do
        stub_request(:post, "https://a.klaviyo.com/api/events/")
          .to_return(status: 429, headers: { "Retry-After" => "60" })
      end

      it "re-raises KlaviyoClient::RateLimitError so Sidekiq retries" do
        expect { described_class.new.perform(action_id: action.id) }
          .to raise_error(KlaviyoClient::RateLimitError)
      end

      it "does not mark the action as executed" do
        described_class.new.perform(action_id: action.id) rescue nil
        expect(action.reload.status).not_to eq("executed")
      end
    end

    # ── API error (HTTP 5xx) ──────────────────────────────────────────────────

    context "when Klaviyo returns 500 (server error)" do
      before do
        stub_request(:post, "https://a.klaviyo.com/api/events/")
          .to_return(status: 500, body: "Internal Server Error")
      end

      it "re-raises KlaviyoClient::ApiError so Sidekiq retries" do
        expect { described_class.new.perform(action_id: action.id) }
          .to raise_error(KlaviyoClient::ApiError)
      end

      it "does not mark the action as executed" do
        described_class.new.perform(action_id: action.id) rescue nil
        expect(action.reload.status).not_to eq("executed")
      end
    end
  end

  # ── sidekiq_retries_exhausted ─────────────────────────────────────────────────
  #
  # Tests the DLQ callback without needing real Sidekiq retry cycles.
  # We call the block directly with a crafted Sidekiq job-hash.

  describe "sidekiq_retries_exhausted" do
    let(:exhausted_msg) do
      {
        "args" => [{
          "job_class" => described_class.name,
          "arguments" => [{ "action_id" => action.id }]
        }]
      }
    end
    let(:last_exception) { KlaviyoClient::ApiError.new("Klaviyo unreachable") }

    def fire_exhausted_callback
      described_class.sidekiq_retries_exhausted_block
                     .call(exhausted_msg, last_exception)
    end

    before { RlsContext.set!(shop.id) }

    it "marks the action as failed" do
      fire_exhausted_callback
      RlsContext.set!(shop.id)
      expect(action.reload.status).to eq("failed")
    end

    it "enqueues an OwnerNotificationJob for the shop" do
      expect {
        fire_exhausted_callback
      }.to have_enqueued_job(OwnerNotificationJob).with(shop_id: shop.id)
    end

    context "when action_id is missing from the message" do
      let(:exhausted_msg) { { "args" => [{ "job_class" => described_class.name, "arguments" => [] }] } }

      it "does not raise" do
        expect { fire_exhausted_callback }.not_to raise_error
      end
    end
  end

  # ── Custom retry backoff ──────────────────────────────────────────────────────

  describe "sidekiq_retry_in" do
    it "doubles the delay with each retry (exponential backoff)" do
      retry_block = described_class.sidekiq_retry_in_block
      expect(retry_block.call(0, nil, nil)).to eq(1)   # 2^0
      expect(retry_block.call(1, nil, nil)).to eq(2)   # 2^1
      expect(retry_block.call(2, nil, nil)).to eq(4)   # 2^2
      expect(retry_block.call(3, nil, nil)).to eq(8)   # 2^3
      expect(retry_block.call(4, nil, nil)).to eq(16)  # 2^4
    end
  end
end
