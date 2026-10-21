require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "changing password revokes refresh tokens" do
    user = users(:one)
    token = user.refresh_tokens.create!(
      token_digest: "password-change-token",
      family_id: "password-change-family",
      expires_at: 1.day.from_now
    )

    user.update!(password: "NewPassword123!")

    assert token.reload.revoked_at.present?
  end

  test "deactivating a user revokes refresh tokens" do
    user = users(:one)
    token = user.refresh_tokens.create!(
      token_digest: "deactivation-token",
      family_id: "deactivation-family",
      expires_at: 1.day.from_now
    )

    user.update!(status: :inactive)

    assert token.reload.revoked_at.present?
  end
end
