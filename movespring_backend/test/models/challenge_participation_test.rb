require "test_helper"

class ChallengeParticipationTest < ActiveSupport::TestCase
  setup do
    @challenge = Challenge.create!(
      company: companies(:one),
      scoring_rule_version: scoring_rule_versions(:one),
      name: "Participation test",
      starts_at: 2.days.from_now,
      ends_at: 9.days.from_now,
      status: "published"
    )
  end

  test "user and challenge must belong to the same company" do
    participation = ChallengeParticipation.new(
      challenge: @challenge,
      user: users(:two)
    )

    assert_not participation.valid?
    assert_includes participation.errors[:user],
                    "must belong to the same company as the challenge"
  end

  test "joining closes at the registration deadline" do
    @challenge.update_column(:registration_deadline, 1.hour.ago)
    participation = ChallengeParticipation.new(
      challenge: @challenge,
      user: users(:one)
    )

    assert_not participation.valid?
    assert_includes participation.errors[:challenge],
                    "is not open for joining"
  end

  test "cannot join a full challenge" do
    @challenge.update_column(:max_participants, 1)
    ChallengeParticipation.create!(
      challenge: @challenge,
      user: users(:one)
    )
    user = User.create!(
      company: companies(:one),
      name: "Another Employee",
      email: "another-employee@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: "employee",
      status: "active"
    )
    participation = ChallengeParticipation.new(
      challenge: @challenge,
      user: user
    )

    assert_not participation.valid?
    assert_includes participation.errors[:challenge], "is full"
  end
end
