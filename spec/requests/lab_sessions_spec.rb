require "rails_helper"

RSpec.describe "Data Lab sessions", type: :request do
  it "renders the public sign-in page without Shopify" do
    get lab_sign_in_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Test retention decisions on your data")
  end

  it "creates a one-time magic link and queues the email" do
    expect do
      post lab_sign_in_path, params: { email: "Owner@Store.COM" }
    end.to change(SandboxUser, :count).by(1)
      .and change(SandboxMagicLink, :count).by(1)
      .and have_enqueued_mail(LabMagicLinkMailer, :sign_in)

    expect(SandboxUser.last.email).to eq("owner@store.com")
    expect(response).to redirect_to(lab_sign_in_path)
  end

  it "consumes a valid token and rejects reuse" do
    user = create(:sandbox_user)
    link, token = SandboxMagicLink.issue_for!(user: user)

    get lab_session_path, params: { token: token }
    expect(response).to redirect_to(lab_root_path)
    expect(link.reload.consumed_at).to be_present

    get lab_session_path, params: { token: token }
    expect(response).to redirect_to(lab_sign_in_path)
  end
end
