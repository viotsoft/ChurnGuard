require "rails_helper"

RSpec.describe OwnerNotificationMailer, type: :mailer do
  let(:shop) { create(:shop, shopify_domain: "acme-store.myshopify.com") }

  before { RlsContext.set!(shop.id) }

  describe "#execution_failed" do
    subject(:mail) do
      described_class.execution_failed(shop: shop, failed_count: 3)
    end

    # ── Routing ───────────────────────────────────────────────────────────────

    it "delivers to the shop owner address" do
      expect(mail.to.first).to include("@")
    end

    it "sends from the ChurnGuard address" do
      expect(mail.from.first).to include("churnguard")
    end

    it "includes the failed count in the subject" do
      expect(mail.subject).to include("3")
    end

    it "includes 'failed' in the subject" do
      expect(mail.subject).to match(/failed/i)
    end

    # ── HTML body ─────────────────────────────────────────────────────────────

    describe "HTML body" do
      subject(:html) { mail.html_part.body.decoded }

      it "uses warm cream #F5F0E8 background (DESIGN.md)" do
        expect(html).to include("#F5F0E8")
      end

      it "uses Fraunces for the heading (DESIGN.md)" do
        expect(html).to include("Fraunces")
      end

      it "uses terracotta #D4500A for the CTA button (DESIGN.md)" do
        expect(html).to include("#D4500A")
      end

      it "includes the failed count" do
        expect(html).to include("3")
      end

      it "mentions retention actions" do
        expect(html).to match(/retention action/i)
      end

      it "includes a link to settings" do
        expect(html).to match(/settings/i)
        expect(html).to include("href=")
      end

      it "mentions the shop domain" do
        expect(html).to include("acme-store.myshopify.com")
      end

      it "uses the plural noun for count > 1" do
        expect(html).to include("retention actions")
      end

      context "with a single failure" do
        subject(:html) do
          described_class.execution_failed(shop: shop, failed_count: 1)
                         .html_part.body.decoded
        end

        it "uses the singular noun" do
          expect(html).to match(/\b1\s+retention action\b/)
        end
      end
    end

    # ── Text body ─────────────────────────────────────────────────────────────

    describe "plain text body" do
      subject(:text) { mail.text_part.body.decoded }

      it "includes the failed count" do
        expect(text).to include("3")
      end

      it "mentions retention actions" do
        expect(text).to match(/retention action/i)
      end

      it "includes a settings URL" do
        expect(text).to match(/settings/i)
      end

      it "includes the shop domain" do
        expect(text).to include("acme-store.myshopify.com")
      end
    end
  end
end
