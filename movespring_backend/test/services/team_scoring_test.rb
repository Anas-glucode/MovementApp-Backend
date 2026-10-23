require "test_helper"
require "securerandom"

# Tests for: ranking teams by average or total, tie handling, the timer dealing
# teams at the start, and the new locked setting.
class TeamScoringTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Team Co", slug: "team-co-test")
    @version = scoring_rule_versions(:one)
  end

  # ---- helpers ----
  def build_user(n)
    User.create!(company: @company, name: "Player #{n}",
                 email: "player-#{n}-team@example.com", password: "password123")
  end

  def build_team_challenge(status: "active", starts_at: 3.days.ago, ends_at: 2.days.from_now)
    Challenge.create!(
      company: @company, scoring_rule_version: @version,
      name: "Teams #{SecureRandom.hex(3)}", status: status,
      challenge_type: "team", starts_at: starts_at, ends_at: ends_at
    )
  end

  def join(challenge, user)
    ChallengeParticipation.new(challenge: challenge, user: user).save!(validate: false)
  end

  def add_team(challenge, name, users)
    team = Team.create!(challenge: challenge, name: name)
    users.each do |user|
      join(challenge, user)
      TeamMembership.new(team: team, user: user, challenge: challenge).save!(validate: false)
    end
    team
  end

  # Gives a user an eligible activity inside the challenge plus an award
  def award(challenge, user, points)
    activity = user.activities.create!(
      activity_type: "walking", source: "manual", status: "eligible",
      started_at: 1.day.ago, ended_at: 1.day.ago + 30.minutes,
      duration_seconds: 1800, reported_intensity: 5
    )

    ChallengeActivityAward.create!(
      challenge: challenge, activity: activity,
      scoring_rule_version: challenge.scoring_rule_version, points: points
    )
  end

  def names_in_order(challenge)
    TeamLeaderboard.call(challenge: challenge).map { |entry| entry[:name] }
  end

  # ---- ranking ----
  test "teams are ranked by average points per member by default" do
    challenge = build_team_challenge
    a1, a2, b1 = build_user(1), build_user(2), build_user(3)

    add_team(challenge, "Team A", [a1, a2]) # 100 points / 2 people = 50 each
    add_team(challenge, "Team B", [b1])     # 70 points / 1 person = 70 each
    award(challenge, a1, 60)
    award(challenge, a2, 40)
    award(challenge, b1, 70)

    # The bigger team has more points in total, but the smaller team is
    # doing better PER PERSON, so it ranks first.
    assert_equal ["Team B", "Team A"], names_in_order(challenge)
  end

  test "teams are ranked by total points when the challenge says so" do
    challenge = build_team_challenge
    challenge.update_columns(team_scoring_method: "total")
    a1, a2, b1 = build_user(1), build_user(2), build_user(3)

    add_team(challenge, "Team A", [a1, a2])
    add_team(challenge, "Team B", [b1])
    award(challenge, a1, 60)
    award(challenge, a2, 40)
    award(challenge, b1, 70)

    assert_equal ["Team A", "Team B"], names_in_order(challenge)
  end

  test "teams with the same average share a rank" do
    challenge = build_team_challenge
    a1, a2, c1 = build_user(1), build_user(2), build_user(3)

    add_team(challenge, "Team A", [a1, a2]) # 100 / 2 = 50
    add_team(challenge, "Team C", [c1])     # 50 / 1 = 50
    award(challenge, a1, 60)
    award(challenge, a2, 40)
    award(challenge, c1, 50)

    ranks = TeamLeaderboard.call(challenge: challenge).map { |entry| entry[:rank] }

    assert_equal [1, 1], ranks
  end

  test "an empty team does not crash the leaderboard" do
    challenge = build_team_challenge
    Team.create!(challenge: challenge, name: "Team Empty")

    entry = TeamLeaderboard.call(challenge: challenge).first

    assert_equal 0, entry[:member_count]
    assert_equal 0.0, entry[:average_points]
  end

  test "inactive members add neither points nor headcount and started activities count" do
    challenge = build_team_challenge
    active_user, inactive_user = build_user(40), build_user(41)
    team = add_team(challenge, "Team A", [active_user, inactive_user])
    inactive_user.update!(status: "inactive")

    crossing_activity = active_user.activities.create!(
      activity_type: "walking",
      source: "manual",
      status: "eligible",
      started_at: challenge.ends_at - 1.hour,
      ended_at: challenge.ends_at + 1.hour,
      duration_seconds: 2.hours.to_i,
      reported_intensity: 5
    )
    ChallengeActivityAward.create!(
      challenge: challenge,
      activity: crossing_activity,
      scoring_rule_version: challenge.scoring_rule_version,
      points: 100
    )
    award(challenge, inactive_user, 500)

    entry = TeamLeaderboard.call(challenge: challenge).first

    assert_equal 1, entry[:member_count]
    assert_equal 100, entry[:points]
    assert_equal 100.0, entry[:average_points]
    assert_equal({ team.id => 100 }, TeamPoints.call(challenge: challenge))
  end

  # ---- visibility ----
  test "employees can see team leaderboards while a challenge is finalizing" do
    assert_includes Api::V1::ChallengesController::VISIBLE_TO_EMPLOYEES, "finalizing"
  end

  # ---- the timer deals teams if the admin forgot ----
  test "the timer deals teams when a team challenge starts with none" do
    challenge = build_team_challenge(status: "published", starts_at: 1.hour.ago, ends_at: 2.days.from_now)
    4.times { |i| join(challenge, build_user(i + 10)) }

    ChallengeLifecycleService.call

    assert_equal "active", challenge.reload.status
    assert_equal 2, challenge.teams.count
    assert_equal 4, TeamMembership.where(challenge: challenge).count
  end

  test "the timer never touches teams an admin already dealt" do
    challenge = build_team_challenge(status: "published", starts_at: 1.hour.ago, ends_at: 2.days.from_now)
    add_team(challenge, "Admin Team", [build_user(20), build_user(21)])

    ChallengeLifecycleService.call

    assert_equal ["Admin Team"], challenge.reload.teams.pluck(:name)
  end

  test "a team challenge with too few people still starts" do
    challenge = build_team_challenge(status: "published", starts_at: 1.hour.ago, ends_at: 2.days.from_now)
    join(challenge, build_user(30))

    ChallengeLifecycleService.call

    assert_equal "active", challenge.reload.status
    assert_equal 0, challenge.teams.count
  end

  # ---- the new locked setting ----
  test "the team scoring method is locked once the challenge is published" do
    challenge = build_team_challenge(status: "draft", starts_at: 1.day.from_now, ends_at: 3.days.from_now)
    challenge.update!(status: "published")

    assert_not challenge.update(team_scoring_method: "total")
    assert_match(/locked/, challenge.errors.full_messages.join)
  end

  test "an unknown team scoring method is refused" do
    challenge = build_team_challenge(status: "draft", starts_at: 1.day.from_now, ends_at: 3.days.from_now)

    assert_not challenge.update(team_scoring_method: "vibes")
  end
end
