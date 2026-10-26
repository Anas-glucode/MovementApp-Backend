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

  test "email change confirmation normalizes the address and revokes refresh tokens" do
    user = users(:one)
    token = user.refresh_tokens.create!(
      token_digest: "email-change-token",
      family_id: "email-change-family",
      expires_at: 1.day.from_now
    )

    user.update!(unconfirmed_email: " New-Address@Example.com ")
    email_change_token = user.generate_token_for(:email_change)

    assert_equal "new-address@example.com", user.unconfirmed_email
    assert_equal user, User.find_by_token_for(:email_change, email_change_token)

    user.update!(unconfirmed_email: "other-address@example.com")
    assert_nil User.find_by_token_for(:email_change, email_change_token)

    email_change_token = user.generate_token_for(:email_change)
    user.confirm_email_change!

    assert_equal "other-address@example.com", user.reload.email
    assert_nil user.unconfirmed_email
    assert user.email_verified?
    assert token.reload.revoked_at.present?
    assert_nil User.find_by_token_for(:email_change, email_change_token)
  end

  test "unconfirmed email cannot be claimed by another user" do
    user = users(:one)

    assert_not user.update(unconfirmed_email: " EMPLOYEE-TWO@example.com ")
    assert_equal "employee-two@example.com", user.unconfirmed_email
    assert_includes user.errors[:email], "is already taken"
  end

  test "confirming an email change without a pending address returns false" do
    assert_not users(:one).confirm_email_change!
  end
end
