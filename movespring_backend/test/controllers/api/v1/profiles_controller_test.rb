require "test_helper"

class Api::V1::ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "profile updates require current password to request an email change" do
    user = users(:one)
    token = TokenService.issue(user)

    patch "/api/v1/me",
          params: {
            user: { name: "Updated Name", email: "new-admin@example.com" },
            current_password: "wrong-password"
          },
          headers: auth_headers(token),
          as: :json

    assert_response :unprocessable_entity
    assert_equal "Current password is incorrect", response.parsed_body["error"]
    assert_equal "admin-one@example.com", user.reload.email
    assert_nil user.unconfirmed_email
  end

  test "profile email change sends confirmation to new address and notice to old address" do
    user = users(:one)
    token = TokenService.issue(user)

    assert_enqueued_emails 2 do
      patch "/api/v1/me",
            params: {
              user: { name: "Updated Name", email: " New-Admin@Example.com " },
              current_password: "Password123!"
            },
            headers: auth_headers(token),
            as: :json
    end

    assert_response :ok
    assert_equal "admin-one@example.com", user.reload.email
    assert_equal "new-admin@example.com", user.unconfirmed_email
    assert_equal "Updated Name", response.parsed_body.dig("user", "name")
    assert_equal "new-admin@example.com",
                 response.parsed_body.dig("user", "pending_email")
  end

  test "password change revokes old tokens and returns fresh credentials" do
    user = users(:one)
    old_token = TokenService.issue(user)
    user.refresh_tokens.create!(
      token_digest: "profile-password-change-token",
      family_id: "profile-password-change-family",
      expires_at: 1.day.from_now
    )

    patch "/api/v1/me/password",
          params: {
            current_password: "Password123!",
            password: "ChangedPassword123!",
            password_confirmation: "ChangedPassword123!"
          },
          headers: auth_headers(old_token),
          as: :json

    assert_response :ok
    assert user.reload.authenticate("ChangedPassword123!")
    assert user.refresh_tokens.first.revoked_at.present?
    assert TokenService.decode(response.parsed_body["token"])
    assert response.parsed_body["refresh_token"].present?

    get "/api/v1/me", headers: auth_headers(old_token)
    assert_response :unauthorized
  end

  test "email change confirmation updates the address and does not require login" do
    user = users(:one)
    user.update!(unconfirmed_email: "new-admin@example.com")
    token = user.generate_token_for(:email_change)
    refresh_token = user.refresh_tokens.create!(
      token_digest: "email-confirmation-refresh-token",
      family_id: "email-confirmation-family",
      expires_at: 1.day.from_now
    )

    post "/api/v1/email_changes/confirm",
         params: { token: token },
         as: :json

    assert_response :ok
    assert_equal "Email address updated. Please log in again.",
                 response.parsed_body["message"]
    assert_equal "new-admin@example.com", user.reload.email
    assert_nil user.unconfirmed_email
    assert refresh_token.reload.revoked_at.present?

    post "/api/v1/email_changes/confirm",
         params: { token: token },
         as: :json

    assert_response :unprocessable_entity
    assert_equal "Invalid or expired confirmation link",
                 response.parsed_body["error"]
  end

  test "email change confirmation rejects an invalid token" do
    post "/api/v1/email_changes/confirm",
         params: { token: "invalid-token" },
         as: :json

    assert_response :unprocessable_entity
    assert_equal "Invalid or expired confirmation link",
                 response.parsed_body["error"]
  end

  private

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
