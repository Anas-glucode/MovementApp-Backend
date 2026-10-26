require "test_helper"

class RefreshTokensTest < ActionDispatch::IntegrationTest
  # Registers a company, logs in, and returns the login response
  def register_and_login
    post "/api/v1/registrations", as: :json, params: {
      company: { name: "Refresh Co" },
      admin: { name: "Admin", email: "admin@refresh.test",
               password: "password123", password_confirmation: "password123" }
    }
    User.find_by!(email: "admin@refresh.test").update!(email_verified_at: Time.current)

    post "/api/v1/sessions", as: :json,
         params: { email: "admin@refresh.test", password: "password123" }
    response.parsed_body
  end

  test "refresh swaps the old ticket for a new one" do
    login = register_and_login

    post "/api/v1/sessions/refresh", as: :json,
         params: { refresh_token: login["refresh_token"] }

    assert_response :ok
    assert response.parsed_body["token"].present?
    assert_not_equal login["refresh_token"], response.parsed_body["refresh_token"]
  end

  test "using an old ticket again cancels the whole family" do
    login = register_and_login
    old = login["refresh_token"]

    post "/api/v1/sessions/refresh", as: :json, params: { refresh_token: old }
    newest = response.parsed_body["refresh_token"]

    # Replaying the old one looks like theft
    post "/api/v1/sessions/refresh", as: :json, params: { refresh_token: old }
    assert_response :unauthorized

    # The newest ticket was cancelled too
    post "/api/v1/sessions/refresh", as: :json, params: { refresh_token: newest }
    assert_response :unauthorized
  end

  test "logout stops the ticket from refreshing" do
    login = register_and_login

    delete "/api/v1/sessions", as: :json,
           params: { refresh_token: login["refresh_token"] },
           headers: { "Authorization" => "Bearer #{login['token']}" }
    assert_response :no_content

    post "/api/v1/sessions/refresh", as: :json,
         params: { refresh_token: login["refresh_token"] }
    assert_response :unauthorized
  end

  test "logout succeeds without a valid access token" do
    login = register_and_login
    access_token = login.fetch("token")
    travel 31.minutes

    delete "/api/v1/sessions", as: :json,
           params: { refresh_token: login["refresh_token"] },
           headers: { "Authorization" => "Bearer #{access_token}" }

    assert_response :no_content
    post "/api/v1/sessions/refresh", as: :json,
         params: { refresh_token: login["refresh_token"] }
    assert_response :unauthorized
  end

  test "logout with an unknown refresh token does not revoke other sessions" do
    login = register_and_login

    delete "/api/v1/sessions", as: :json,
           params: { refresh_token: "unknown-refresh-token" }

    assert_response :no_content
    post "/api/v1/sessions/refresh", as: :json,
         params: { refresh_token: login["refresh_token"] }
    assert_response :ok
  end

  test "changing the password cancels refresh tokens" do
    login = register_and_login

    User.find_by(email: "admin@refresh.test")
        .update!(password: "newpassword456", password_confirmation: "newpassword456")

    post "/api/v1/sessions/refresh", as: :json,
         params: { refresh_token: login["refresh_token"] }
    assert_response :unauthorized
  end
end