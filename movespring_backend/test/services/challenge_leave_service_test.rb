require "test_helper"

class ChallengeLeaveServiceTest < ActiveSupport::TestCase
  setup do
    @challenge = Challenge.create!(
      company: companies(:one),
      scoring_rule_version: scoring_rule_versions(:one),
      name: "Leave service test",
      starts_at: 2.days.from_now,
      ends_at: 9.days.from_now,
      status: "published"
    )
  end

  test "leaving removes the participation and team membership" do
    user = users(:one)
    participation = ChallengeParticipation.create!(
      challenge: @challenge,
      user: user
    )
    team = @challenge.teams.create!(name: "Team 1")
    membership = team.team_memberships.create!(
      challenge: @challenge,
      user: user
    )

    assert_equal({ left: true }, ChallengeLeaveService.call(challenge: @challenge, user: user))
    assert_not ChallengeParticipation.exists?(participation.id)
    assert_not TeamMembership.exists?(membership.id)
  end

  test "returns not joined when the user has not joined" do
    result = ChallengeLeaveService.call(challenge: @challenge, user: users(:one))

    assert_equal :not_joined, result[:reason]
    assert_equal ["You have not joined this challenge"], result[:errors]
  end

  test "returns closed after the challenge starts" do
    @challenge.update_column(:starts_at, 1.hour.ago)

    result = ChallengeLeaveService.call(challenge: @challenge, user: users(:one))

    assert_equal :closed, result[:reason]
    assert_equal ["You can only leave a challenge before it starts"], result[:errors]
  end
end
