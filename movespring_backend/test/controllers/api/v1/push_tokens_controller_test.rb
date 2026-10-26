require "test_helper"

class Api::V1::PushTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:two)
    @token = "ExponentPushToken[#{SecureRandom.uuid}]"
  end

  test "user can register and unregister an Expo push token" do
    post api_v1_push_tokens_path,
         params: { push_token: { token: @token } },
         headers: auth_headers

    assert_response :created
    assert PushToken.exists?(user: @user, token: @token)

    delete api_v1_push_tokens_path,
           params: { push_token: { token: @token } },
           headers: auth_headers

    assert_response :no_content
    assert_not PushToken.exists?(user: @user, token: @token)
  end

  test "invalid Expo tokens are rejected" do
    post api_v1_push_tokens_path,
         params: { push_token: { token: "not-an-expo-token" } },
         headers: auth_headers

    assert_response :unprocessable_entity
  end

  test "registration transfers a token when the device switches accounts" do
    PushToken.create!(user: @user, token: @token)
    other_user = users(:one)

    post api_v1_push_tokens_path,
         params: { push_token: { token: @token } },
         headers: { "Authorization" => "Bearer #{TokenService.issue(other_user)}" }

    assert_response :created
    assert_equal other_user.id, PushToken.find_by!(token: @token).user_id
    assert_equal 1, PushToken.where(token: @token).count
  end

  test "re-registering the same token for the same user is idempotent" do
    2.times do
      post api_v1_push_tokens_path,
           params: { push_token: { token: @token } },
           headers: auth_headers
      assert_response :created
    end

    assert_equal 1, PushToken.where(user: @user, token: @token).count
  end

  test "deleting another user's token does not remove it" do
    PushToken.create!(user: users(:one), token: @token)

    delete api_v1_push_tokens_path,
           params: { push_token: { token: @token } },
           headers: auth_headers

    assert_response :no_content
    assert PushToken.exists?(user: users(:one), token: @token)
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{TokenService.issue(@user)}" }
  end
end
