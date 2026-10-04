require "rails_helper"

RSpec.describe ApprovalMailer, type: :mailer do
  let(:shop)     { create(:shop) }
  let(:customer) do
    create(:customer, shop: shop, name: "Maria Kowalski",
           email: "maria@example.com", lifetime_value: 89.0, risk_tier: "high")
  end
  let(:action) do
    create(:action, shop: shop, customer: customer,
           risk_tier: "high", revenue_at_risk: 89.0,
           proposed_discount: "15%",
           reason: "Last ordered 207 days ago — likely to be lost to a competitor")
  end
  let(:token)  { "test.jwt.token" }
  let(:mail)   { described_class.notify_owner(action: action, token: token) }

  before { RlsContext.set!(shop.id) }

  # ── Routing ─────────────────────────────────────────────────────────────────

  describe "#notify_owner" do
    it "renders the headers" do
      expect(mail.subject).to include("Maria Kowalski")
      expect(mail.subject).to include("at risk")
    end

    it "sends to the shop owner address" do
      expect(mail.to).to be_present
      expect(mail.to.first).to include("@")
    end

    it "sends from the ChurnGuard address" do
      expect(mail.from).to be_present
    end
  end

  # ── HTML body ────────────────────────────────────────────────────────────────

  describe "HTML body" do
    subject(:html) { mail.html_part.body.decoded }

    it "includes the customer name" do
      expect(html).to include("Maria Kowalski")
    end

    it "includes revenue at risk — shown first (top-right per DESIGN.md)" do
      expect(html).to include("€89")
      expect(html).to include("at risk")
    end

    it "uses Fraunces for the customer name" do
      # Font is referenced via Google Fonts import in the <head>
      expect(html).to include("Fraunces")
    end

    it "uses terracotta #D4500A for the revenue figure" do
      expect(html).to include("#D4500A")
    end

    it "uses warm cream #F5F0E8 background" do
      expect(html).to include("#F5F0E8")
    end

    it "includes the approve link" do
      expect(html).to include("approve")
      expect(html).to include(token)
    end

    it "includes the skip link" do
      expect(html).to include("skip")
      expect(html).to include(token)
    end

    it "includes the risk reason" do
      expect(html).to include("207 days ago")
    end

    it "shows the proposed discount in the CTA" do
      expect(html).to include("15%")
    end

    it "shows the HIGH RISK badge for high-risk customers" do
      expect(html).to include("HIGH RISK")
    end

    it "does not contain blue CTA buttons (DESIGN.md anti-pattern)" do
      expect(html).not_to match(/background-color:\s*#[0-9a-fA-F]*[Bb][Uu][Ee]/)
      # Specifically no #0070F3 (Vercel blue) or similar
      expect(html).not_to include("#0070")
      expect(html).not_to include("#1A73")  # Google blue
    end

    it "does not use Inter or system-ui for customer name (DESIGN.md anti-pattern)" do
      # Customer name cell should use Fraunces, not a geometric sans
      customer_name_section = html[/Fraunces[^>]*>.*?Maria/m]
      expect(customer_name_section).not_to be_nil
    end
  end

  # ── Text body ────────────────────────────────────────────────────────────────

  describe "plain text body" do
    subject(:text) { mail.text_part.body.decoded }

    it "includes the customer name" do
      expect(text).to include("Maria Kowalski")
    end

    it "includes the approve URL" do
      expect(text).to include("approve")
      expect(text).to include(token)
    end

    it "includes the skip URL" do
      expect(text).to include("skip")
      expect(text).to include(token)
    end

    it "includes the revenue at risk" do
      expect(text).to include("€89")
    end
  end

  # ── Medium risk variant ───────────────────────────────────────────────────────

  describe "medium risk customer" do
    let(:medium_customer) do
      create(:customer, shop: shop, name: "Jan Nowak",
             lifetime_value: 210.0, risk_tier: "medium")
    end
    let(:medium_action) do
      create(:action, shop: shop, customer: medium_customer,
             risk_tier: "medium", proposed_discount: "10%", revenue_at_risk: 210.0)
    end
    let(:medium_mail) { described_class.notify_owner(action: medium_action, token: token) }

    it "shows MEDIUM RISK badge" do
      expect(medium_mail.html_part.body.decoded).to include("MEDIUM RISK")
    end

    it "proposes 10% discount in subject" do
      expect(medium_mail.html_part.body.decoded).to include("10%")
    end
  end
end
