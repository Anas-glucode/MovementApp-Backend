require "test_helper"
require "securerandom"

# Tests for the challenge lifecycle: automatic status changes, the
# finalizing stage, and the model rules that protect a running challenge.
class ChallengeLifecycleTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Life Co", slug: "life-co-test")
    @user = User.create!(company: @company, name: "Walker",
                         email: "walker-life@example.com",
                         password: "password123")
  end

  # ---- helpers ----
  def build_challenge(status:, starts_at:, ends_at:)
    Challenge.create!(
      company: @company,
      scoring_rule_version: scoring_rule_versions(:one),
      name: "Challenge #{SecureRandom.hex(3)}",
      status: status,
      starts_at: starts_at,
      ends_at: ends_at
    )
  end

  def join(challenge)
    ChallengeParticipation.new(challenge: challenge, user: @user)
                          .save!(validate: false)
  end

  def log_walk
    started_at = 1.hour.ago

    ActivityCreationService.call(
      user: @user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: started_at,
        ended_at: started_at + 30.minutes,
        reported_intensity: 5
      }
    )
  end

  # ---- the timer ----
  test "a published challenge becomes active once its start time passes" do
    challenge = build_challenge(status: "published", starts_at: 1.hour.ago, ends_at: 2.days.from_now)

    ChallengeLifecycleService.call

    assert_equal "active", challenge.reload.status
  end

  test "a published challenge that has not started yet stays published" do
    challenge = build_challenge(status: "published", starts_at: 1.day.from_now, ends_at: 3.days.from_now)

    ChallengeLifecycleService.call

    assert_equal "published", challenge.reload.status
  end

  test "an active challenge becomes finalizing, not completed, when it ends" do
    challenge = build_challenge(status: "active", starts_at: 3.days.ago, ends_at: 1.hour.ago)

    ChallengeLifecycleService.call

    assert_equal "finalizing", challenge.reload.status
    assert_nil challenge.finalized_at
  end

  test "a published challenge whose whole window has passed catches up to finalizing" do
    challenge = build_challenge(status: "published", starts_at: 3.days.ago, ends_at: 1.hour.ago)

    ChallengeLifecycleService.call

    assert_equal "finalizing", challenge.reload.status
  end

  test "a finalizing challenge completes after the grace period when nothing awaits review" do
    challenge = build_challenge(status: "finalizing", starts_at: 5.days.ago, ends_at: 3.days.ago)

    ChallengeLifecycleService.call

    assert_equal "completed", challenge.reload.status
    assert challenge.finalized_at.present?
  end

  test "a finalizing challenge stays finalizing while the grace period runs" do
    challenge = build_challenge(status: "finalizing", starts_at: 3.days.ago, ends_at: 1.hour.ago)

    ChallengeLifecycleService.call

    assert_equal "finalizing", challenge.reload.status
  end

  test "a finalizing challenge waits while an activity is still waiting for review" do
    challenge = build_challenge(status: "finalizing", starts_at: 5.days.ago, ends_at: 3.days.ago)
    join(challenge)

    @user.activities.create!(
      activity_type: "walking", source: "manual", status: "under_review",
      started_at: 4.days.ago, ended_at: 4.days.ago + 30.minutes,
      duration_seconds: 1800
    )

    ChallengeLifecycleService.call

    assert_equal "finalizing", challenge.reload.status
  end

  # ---- which statuses accept points ----
  test "a finalizing challenge still takes points" do
    challenge = build_challenge(status: "finalizing", starts_at: 3.days.ago, ends_at: 10.minutes.ago)
    join(challenge)

    activity = log_walk[:activity]

    assert_equal 1, ChallengeActivityAward.where(challenge: challenge, activity: activity).count
  end

  test "a completed challenge takes no points" do
    challenge = build_challenge(status: "completed", starts_at: 3.days.ago, ends_at: 10.minutes.ago)
    join(challenge)

    activity = log_walk[:activity]

    assert_equal 0, ChallengeActivityAward.where(challenge: challenge, activity: activity).count
  end

  # ---- model protections ----
  test "an illegal status jump is refused" do
    challenge = build_challenge(status: "draft", starts_at: 1.day.from_now, ends_at: 3.days.from_now)

    assert_not challenge.update(status: "completed")
    assert_match(/cannot move from draft to completed/, challenge.errors.full_messages.join)
  end

  test "a completed challenge cannot be reopened" do
    challenge = build_challenge(status: "completed", starts_at: 5.days.ago, ends_at: 3.days.ago)

    assert_not challenge.update(status: "active")
  end

  test "dates are locked once the challenge is published" do
    challenge = build_challenge(status: "draft", starts_at: 1.day.from_now, ends_at: 3.days.from_now)
    challenge.update!(status: "published")

    assert_not challenge.update(ends_at: 5.days.from_now)
    assert_match(/locked/, challenge.errors.full_messages.join)
  end

  test "name and description can still be edited after publishing" do
    challenge = build_challenge(status: "draft", starts_at: 1.day.from_now, ends_at: 3.days.from_now)
    challenge.update!(status: "published")

    assert challenge.update(name: "Better name", description: "Clearer text")
  end
end
