require "test_helper"

# Tests for team membership integrity, safe reshuffling and repeated formation.
class TeamIntegrityTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Integrity Co", slug: "integrity-co-test")
    @other_company = Company.create!(name: "Other Co", slug: "other-co-test")
    @version = scoring_rule_versions(:one)
    @challenge = Challenge.create!(
      company: @company, scoring_rule_version: @version,
      name: "Integrity Challenge", status: "published",
      challenge_type: "team", starts_at: 2.days.from_now, ends_at: 5.days.from_now
    )
  end

  # ---- helpers ----
  def build_user(n, company: @company)
    User.create!(company: company, name: "Player #{n}",
                 email: "player-#{n}-integrity@example.com", password: "password123")
  end

  # A proper sign-up, with every normal check
  def sign_up(user)
    ChallengeParticipation.create!(challenge: @challenge, user: user)
  end

  # A sign-up that skips the checks, to build situations the app should
  # never produce but other code paths might
  def sign_up_unchecked(user)
    ChallengeParticipation.new(challenge: @challenge, user: user).save!(validate: false)
  end

  def form_teams(**options)
    TeamFormationService.call(challenge: @challenge, **options)
  end

  # ---- membership validations ----
  test "a deactivated person cannot be put on a team" do
    user = build_user(1)
    sign_up(user)
    user.update!(status: "inactive")
    team = Team.create!(challenge: @challenge, name: "Team A")

    membership = TeamMembership.new(team: team, user: user, challenge: @challenge)

    assert_not membership.valid?
    assert_includes membership.errors.full_messages, "User must be active"
  end

  test "a person from another company cannot be put on a team" do
    outsider = build_user(2, company: @other_company)
    sign_up_unchecked(outsider)
    team = Team.create!(challenge: @challenge, name: "Team A")

    membership = TeamMembership.new(team: team, user: outsider, challenge: @challenge)

    assert_not membership.valid?
    assert_includes membership.errors.full_messages,
                    "User must belong to the same company as the challenge"
  end

  test "an existing membership stays valid after the person is deactivated" do
    user = build_user(3)
    sign_up(user)
    team = Team.create!(challenge: @challenge, name: "Team A")
    membership = TeamMembership.create!(team: team, user: user, challenge: @challenge)

    user.update!(status: "inactive")

    assert membership.reload.valid?
  end

  test "the database refuses a second team for the same person in a challenge" do
    user = build_user(4)
    sign_up(user)
    team_a = Team.create!(challenge: @challenge, name: "Team A")
    team_b = Team.create!(challenge: @challenge, name: "Team B")
    TeamMembership.create!(team: team_a, user: user, challenge: @challenge)

    second = TeamMembership.new(team: team_b, user: user, challenge: @challenge)

    assert_not second.valid?
    assert_raises(ActiveRecord::RecordNotUnique) { second.save!(validate: false) }
  end

  # ---- reshuffling ----
  test "a failed reshuffle leaves the original teams and memberships untouched" do
    4.times { |i| sign_up(build_user(10 + i)) }
    assert form_teams(team_count: 2)[:teams]

    original_team_ids = @challenge.teams.pluck(:id).sort
    original_memberships = TeamMembership.where(challenge: @challenge).pluck(:id).sort

    # Someone from another company sneaks into the sign-ups. Dealing them
    # fails halfway through the reshuffle.
    sign_up_unchecked(build_user(20, company: @other_company))

    result = form_teams(team_count: 2, reshuffle: true)

    assert result[:errors].present?
    assert_equal original_team_ids, @challenge.teams.reload.pluck(:id).sort
    assert_equal original_memberships, TeamMembership.where(challenge: @challenge).pluck(:id).sort
  end

  test "a successful reshuffle replaces every team and keeps everyone on exactly one" do
    users = Array.new(4) { |i| build_user(30 + i) }
    users.each { |user| sign_up(user) }
    form_teams(team_count: 2)
    old_team_ids = @challenge.teams.pluck(:id)

    result = form_teams(team_count: 2, reshuffle: true)

    assert result[:teams]
    assert_empty(old_team_ids & @challenge.teams.reload.pluck(:id))
    assert_equal 4, TeamMembership.where(challenge: @challenge).count
    assert_equal users.map(&:id).sort, TeamMembership.where(challenge: @challenge).pluck(:user_id).sort
  end

  # ---- repeated formation and joining ----
  test "forming teams a second time without reshuffle is refused and changes nothing" do
    4.times { |i| sign_up(build_user(40 + i)) }
    form_teams(team_count: 2)
    team_ids = @challenge.teams.pluck(:id).sort

    second = form_teams(team_count: 2)

    assert_includes second[:errors], "Teams already exist. Send reshuffle: true to rebuild them"
    assert_equal team_ids, @challenge.teams.reload.pluck(:id).sort
  end

  test "someone who joins after the teams are dealt lands on the smallest team" do
    3.times { |i| sign_up(build_user(50 + i)) } # two teams: sizes 2 and 1
    form_teams(team_count: 2)

    latecomer = build_user(60)
    sign_up(latecomer)
    team = TeamAssignmentService.call(challenge: @challenge, user: latecomer)

    assert team.present?
    sizes = @challenge.teams.reload.map { |t| t.team_memberships.count }.sort
    assert_equal [2, 2], sizes
  end

  test "forming teams is refused once the challenge has started" do
    4.times { |i| sign_up(build_user(70 + i)) }
    @challenge.update_columns(status: "active", starts_at: 1.hour.ago)

    result = form_teams(team_count: 2)

    assert result[:errors].present?
    assert_equal 0, @challenge.teams.count
  end
end
