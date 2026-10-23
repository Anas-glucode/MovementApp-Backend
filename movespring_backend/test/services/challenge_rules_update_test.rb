require "test_helper"
require "securerandom"

# Tests for: the "counts if it starts inside the challenge" rule, deactivated
# people dropping out of the leaderboards, registration deadlines, maximum
# participants, and leaving a challenge.
class ChallengeRulesUpdateTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Rules Co", slug: "rules-co-test")
    @version = scoring_rule_versions(:one)
    @user = build_user(0)
  end

  # ---- helpers ----
  def build_user(n)
    User.create!(company: @company, name: "Player #{n}",
                 email: "player-#{n}-rules@example.com", password: "password123")
  end

  def build_challenge(status:, starts_at:, ends_at:, **extra)
    Challenge.create!(
      company: @company, scoring_rule_version: @version,
      name: "Challenge #{SecureRandom.hex(3)}", status: status,
      starts_at: starts_at, ends_at: ends_at, **extra
    )
  end

  # Joins skipping the "is it open?" checks, for challenges already running
  def join_directly(challenge, user)
    ChallengeParticipation.new(challenge: challenge, user: user).save!(validate: false)
  end

  def log_activity(user: @user, started_at:, ended_at:)
    ActivityCreationService.call(
      user: user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: started_at,
        ended_at: ended_at,
        reported_intensity: 5
      }
    )
  end

  def awards_for(challenge)
    ChallengeActivityAward.where(challenge: challenge).count
  end

  # ---- the boundary rule ----
  test "an activity that starts inside the challenge and ends after it still counts" do
    challenge = build_challenge(status: "finalizing", starts_at: 3.days.ago, ends_at: 10.minutes.ago)
    join_directly(challenge, @user)

    result = log_activity(started_at: 20.minutes.ago, ended_at: 5.minutes.ago)

    assert result[:activity].present?, result[:errors].inspect
    assert_equal 1, awards_for(challenge)
  end

  test "an activity that starts before the challenge does not count" do
    challenge = build_challenge(status: "active", starts_at: 10.minutes.ago, ends_at: 1.day.from_now)
    join_directly(challenge, @user)

    result = log_activity(started_at: 20.minutes.ago, ended_at: 5.minutes.ago)

    assert result[:activity].present?, "the activity itself is still saved"
    assert_equal 0, awards_for(challenge)
  end

  test "an activity that starts after the challenge ended does not count" do
    challenge = build_challenge(status: "finalizing", starts_at: 3.days.ago, ends_at: 1.hour.ago)
    join_directly(challenge, @user)

    log_activity(started_at: 30.minutes.ago, ended_at: 10.minutes.ago)

    assert_equal 0, awards_for(challenge)
  end

  test "scoring directly names the start rule when an activity starts outside" do
    challenge = build_challenge(status: "active", starts_at: 10.minutes.ago, ends_at: 1.day.from_now)
    join_directly(challenge, @user)
    activity = log_activity(started_at: 20.minutes.ago, ended_at: 5.minutes.ago)[:activity]

    error = assert_raises(ChallengeActivityScoringService::ScoringError) do
      ChallengeActivityScoringService.call(challenge: challenge, activity: activity)
    end

    assert_equal "Activity must start within the challenge dates", error.message
  end

  test "team points use the same start rule" do
    challenge = build_challenge(status: "active", starts_at: 3.days.ago, ends_at: 90.minutes.ago,
                                challenge_type: "team")
    team = Team.create!(challenge: challenge, name: "Team A")
    join_directly(challenge, @user)
    TeamMembership.new(team: team, user: @user, challenge: challenge).save!(validate: false)

    # Starts before the end (2h ago), ends after it (1h ago)
    activity = @user.activities.create!(
      activity_type: "walking", source: "manual", status: "eligible",
      started_at: 2.hours.ago, ended_at: 1.hour.ago,
      duration_seconds: 3600, reported_intensity: 5
    )
    ChallengeActivityAward.create!(challenge: challenge, activity: activity,
                                   scoring_rule_version: @version, points: 50)

    assert_equal({ team.id => 50 }, TeamPoints.call(challenge: challenge))
  end

  # ---- deactivated people ----
  test "a deactivated member leaves the team average, headcount and points" do
    challenge = build_challenge(status: "active", starts_at: 3.days.ago, ends_at: 2.days.from_now,
                                challenge_type: "team")
    team = Team.create!(challenge: challenge, name: "Team A")
    leaver = build_user(1)

    [@user, leaver].each do |user|
      join_directly(challenge, user)
      TeamMembership.new(team: team, user: user, challenge: challenge).save!(validate: false)
    end

    [[@user, 60], [leaver, 40]].each do |user, points|
      activity = user.activities.create!(
        activity_type: "walking", source: "manual", status: "eligible",
        started_at: 1.day.ago, ended_at: 1.day.ago + 30.minutes,
        duration_seconds: 1800, reported_intensity: 5
      )
      ChallengeActivityAward.create!(challenge: challenge, activity: activity,
                                     scoring_rule_version: @version, points: points)
    end

    leaver.update!(status: "inactive")

    entry = TeamLeaderboard.call(challenge: challenge).first

    assert_equal 1, entry[:member_count]
    assert_equal 60, entry[:points]
    assert_equal 60.0, entry[:average_points]
  end

  test "the individual leaderboard leaves out deactivated people and counts starts" do
    challenge = build_challenge(status: "active", starts_at: 3.days.ago, ends_at: 2.days.from_now)
    leaver = build_user(2)
    [@user, leaver].each { |user| join_directly(challenge, user) }

    [@user, leaver].each do |user|
      activity = user.activities.create!(
        activity_type: "walking", source: "manual", status: "eligible",
        started_at: 1.day.ago, ended_at: 1.day.ago + 30.minutes,
        duration_seconds: 1800, reported_intensity: 5
      )
      ChallengeActivityAward.create!(challenge: challenge, activity: activity,
                                     scoring_rule_version: @version, points: 30)
    end

    leaver.update!(status: "inactive")

    names = ChallengeLeaderboard.call(challenge: challenge).map { |entry| entry[:name] }

    assert_equal [@user.name], names
  end

  # ---- registration deadline ----
  test "nobody can join after the registration deadline, even before the start" do
    challenge = build_challenge(status: "published", starts_at: 2.days.from_now,
                                ends_at: 5.days.from_now, registration_deadline: 1.hour.ago)

    participation = ChallengeParticipation.new(challenge: challenge, user: @user)

    assert_not participation.valid?
    assert_includes participation.errors.full_messages, "Challenge is not open for joining"
  end

  test "people can join before the registration deadline" do
    challenge = build_challenge(status: "published", starts_at: 2.days.from_now,
                                ends_at: 5.days.from_now, registration_deadline: 1.day.from_now)

    assert ChallengeParticipation.new(challenge: challenge, user: @user).valid?
  end

  test "with no deadline, joining stays open until the start" do
    challenge = build_challenge(status: "published", starts_at: 2.days.from_now, ends_at: 5.days.from_now)

    assert challenge.open_for_joining?
    assert_equal challenge.starts_at, challenge.registration_closes_at
  end

  test "a deadline after the start is refused" do
    challenge = build_challenge(status: "draft", starts_at: 2.days.from_now, ends_at: 5.days.from_now)

    assert_not challenge.update(registration_deadline: 3.days.from_now)
  end

  # ---- maximum participants ----
  test "a full challenge turns people away" do
    challenge = build_challenge(status: "published", starts_at: 2.days.from_now,
                                ends_at: 5.days.from_now, max_participants: 2)

    ChallengeParticipation.create!(challenge: challenge, user: @user)
    ChallengeParticipation.create!(challenge: challenge, user: build_user(3))

    extra = ChallengeParticipation.new(challenge: challenge, user: build_user(4))

    assert_not extra.valid?
    assert_includes extra.errors.full_messages, "Challenge is full"
  end

  test "a challenge with room accepts people" do
    challenge = build_challenge(status: "published", starts_at: 2.days.from_now,
                                ends_at: 5.days.from_now, max_participants: 2)

    assert ChallengeParticipation.new(challenge: challenge, user: @user).valid?
  end

  test "deadline and maximum are locked once the challenge is published" do
    challenge = build_challenge(status: "draft", starts_at: 2.days.from_now, ends_at: 5.days.from_now)
    challenge.update!(status: "published")

    assert_not challenge.update(max_participants: 10)
    assert_not challenge.update(registration_deadline: 1.day.from_now)
  end

  # ---- leaving ----
  test "leaving before the start removes the person and their team spot" do
    challenge = build_challenge(status: "published", starts_at: 2.days.from_now,
                                ends_at: 5.days.from_now, challenge_type: "team")
    ChallengeParticipation.create!(challenge: challenge, user: @user)
    team = Team.create!(challenge: challenge, name: "Team A")
    TeamMembership.create!(team: team, user: @user, challenge: challenge)

    result = ChallengeLeaveService.call(challenge: challenge, user: @user)

    assert result[:left]
    assert_equal 0, ChallengeParticipation.where(challenge: challenge).count
    assert_equal 0, TeamMembership.where(challenge: challenge).count
  end

  test "leaving after the start is refused" do
    challenge = build_challenge(status: "active", starts_at: 1.hour.ago, ends_at: 2.days.from_now)
    join_directly(challenge, @user)

    result = ChallengeLeaveService.call(challenge: challenge, user: @user)

    assert_equal :closed, result[:reason]
    assert_equal 1, ChallengeParticipation.where(challenge: challenge).count
  end

  test "leaving a challenge you never joined is refused" do
    challenge = build_challenge(status: "published", starts_at: 2.days.from_now, ends_at: 5.days.from_now)

    result = ChallengeLeaveService.call(challenge: challenge, user: @user)

    assert_equal :not_joined, result[:reason]
  end

  test "someone who left can join again while registration is open" do
    challenge = build_challenge(status: "published", starts_at: 2.days.from_now, ends_at: 5.days.from_now)
    ChallengeParticipation.create!(challenge: challenge, user: @user)
    ChallengeLeaveService.call(challenge: challenge, user: @user)

    assert ChallengeParticipation.new(challenge: challenge, user: @user).valid?
  end
end
