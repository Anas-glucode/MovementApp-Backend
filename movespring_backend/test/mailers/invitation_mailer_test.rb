require "test_helper"

class InvitationMailerTest < ActionMailer::TestCase
  test "marks invitation sent after successful delivery" do
    invitation = Invitation.create!(
      company: companies(:one),
      invited_by: users(:one),
      email: "invitee@example.com",
      role: "employee",
      expires_at: 7.days.from_now
    )

    assert_nil invitation.email_sent_at

    InvitationMailer.invite(invitation, invitation.raw_token).deliver_now

    assert invitation.reload.email_sent_at.present?
  end
end
