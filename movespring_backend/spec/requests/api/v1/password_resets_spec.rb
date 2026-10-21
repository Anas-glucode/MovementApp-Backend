require "rails_helper"

RSpec.describe "Api::V1::PasswordResets", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { Company.create!(name: "Password Reset Co") }
  let(:user) do
    company.users.create!(
      name: "Reset User",
      email: "reset-user@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: "employee",
      status: "active"
    )
  end

  describe "POST /api/v1/password_resets" do
    it "returns a generic response and enqueues an email for an active user" do
      user

      expect do
        post "/api/v1/password_resets",
             params: { email: " RESET-USER@example.com " },
             as: :json
      end.to have_enqueued_mail(PasswordMailer, :reset)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "message" => "If that email exists, a reset link has been sent"
      )
    end

    it "returns the same response for an unknown email" do
      expect do
        post "/api/v1/password_resets",
             params: { email: "unknown@example.com" },
             as: :json
      end.not_to have_enqueued_mail(PasswordMailer, :reset)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "message" => "If that email exists, a reset link has been sent"
      )
      expect(response.body).not_to include("unknown@example.com")
    end
  end

  describe "PATCH /api/v1/password_resets" do
    it "updates the password and invalidates existing refresh tokens" do
      user.refresh_tokens.create!(
        token_digest: "reset-password-refresh-token",
        family_id: "reset-password-family",
        expires_at: 1.day.from_now
      )
      token = user.password_reset_token

      patch "/api/v1/password_resets",
            params: {
              token: token,
              password: "UpdatedPassword123!",
              password_confirmation: "UpdatedPassword123!"
            },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.authenticate("UpdatedPassword123!")).to be_truthy
      expect(user.refresh_tokens.first.revoked_at).to be_present
      expect(User.find_by_password_reset_token(token)).to be_nil
    end

    it "accepts each reset token only once" do
      token = user.password_reset_token
      params = {
        token: token,
        password: "UpdatedPassword123!",
        password_confirmation: "UpdatedPassword123!"
      }

      patch "/api/v1/password_resets", params: params, as: :json
      expect(response).to have_http_status(:ok)

      patch "/api/v1/password_resets", params: params, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Invalid or expired token")
    end

    it "rejects an expired reset token" do
      token = user.password_reset_token

      travel 16.minutes do
        patch "/api/v1/password_resets",
              params: {
                token: token,
                password: "UpdatedPassword123!",
                password_confirmation: "UpdatedPassword123!"
              },
              as: :json
      end

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Invalid or expired token")
    end

    it "rejects an invalid reset token" do
      patch "/api/v1/password_resets",
            params: { token: "invalid-token", password: "UpdatedPassword123!" },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Invalid or expired token")
    end
  end
end
