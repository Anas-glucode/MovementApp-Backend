require "test_helper"
require "securerandom"

# Tests for: per-challenge failure isolation, completed challenges refusing
# points, and the company time zone driving the daily cap.
#
# The challenge helper below skips validations (save!(validate: false)) because
# I haven't seen your Challenge and ChallengeParticipation rules. If you have
# fixtures or test helpers for active challenges, swap them in.
class ChallengeScoringAndTimeZoneTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Zone Co", slug: "zone-co-test",
                               time_zone: "UTC")
    @user = User.create!(company: @company, name: "Runner",
                         email: "runner-zone@example.com",
                         password: "password123")
    @good_version = scoring_rule_versions(:one)
  end

  # ---- helpers ----
  def build_challenge(status:, version: @good_version)
    challenge = Challenge.new(
      company: @company,
      scoring_rule_version: version,
      name: "Challenge #{SecureRandom.hex(3)}",
      status: status,
      starts_at: 3.days.ago,
      ends_at: 1.day.from_now
    )
    challenge.save!(validate: false)

    ChallengeParticipation.new(challenge: challenge, user: @user)
                          .save!(validate: false)

    challenge
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

  # ---- one broken challenge must not block the activity ----
  test "a broken challenge does not stop the activity or the other challenges" do
    # A retired version whose rules we then break on purpose
    broken_version = ScoringRuleVersion.create!(
      name: "Broken", version_number: 60, status: "retired",
      published_at: Time.current, rules: @good_version.rules
    )
    broken_version.update_columns(rules: {})

    broken_challenge = build_challenge(status: "active", version: broken_version)
    healthy_challenge = build_challenge(status: "active")

    result = log_walk
    activity = result[:activity]

    assert activity.present?, result[:errors].inspect
    assert activity.activity_point_award.present?, "personal points should still be awarded"

    assert_equal 1, ChallengeActivityAward.where(activity: activity, challenge: healthy_challenge).count
    assert_equal 0, ChallengeActivityAward.where(activity: activity, challenge: broken_challenge).count
  end

  # ---- completed challenges are closed ----
  test "a completed challenge takes no new points" do
    completed = build_challenge(status: "completed")

    activity = log_walk[:activity]

    assert activity.present?
    assert_equal 0, ChallengeActivityAward.where(challenge: completed).count

    error = assert_raises(ChallengeActivityScoringService::ScoringError) do
      ChallengeActivityScoringService.call(challenge: completed, activity: activity)
    end
    assert_equal "Challenge is not available for scoring", error.message
  end

  test "an active challenge still takes points" do
    active = build_challenge(status: "active")

    activity = log_walk[:activity]

    assert_equal 1, ChallengeActivityAward.where(challenge: active, activity: activity).count
  end

  # ---- company time zone drives the daily cap ----
  test "the cap day follows the company time zone, not the one the phone sends" do
    @company.update!(time_zone: "Africa/Johannesburg") # UTC+2

    # 23:30 UTC on 20 Oct is 01:30 on 21 Oct in Johannesburg.
    # The phone claims Auckland; that claim must be ignored.
    activity = @user.activities.new(started_at: Time.utc(2026, 10, 20, 23, 30),
                                    time_zone: "Pacific/Auckland")

    assert_equal Date.new(2026, 10, 21), DailyPointCap.day_range(activity).begin.to_date
  end

  test "the cap day is 25 hours long when the company's clocks go back" do
    @company.update!(time_zone: "America/New_York")

    activity = @user.activities.new(started_at: Time.utc(2026, 11, 1, 12, 0))
    range = DailyPointCap.day_range(activity)

    assert_in_delta 25.hours.to_f, (range.end - range.begin), 1.0
  end

  test "an activity near midnight counts toward the day it started in the company zone" do
    @company.update!(time_zone: "America/New_York")

    # 03:30 UTC on 21 Oct is 23:30 on 20 Oct in New York (UTC-4)
    activity = @user.activities.new(started_at: Time.utc(2026, 10, 21, 3, 30))

    assert_equal Date.new(2026, 10, 20), DailyPointCap.day_range(activity).begin.to_date
  end

  test "a missing or unrecognised company zone falls back to UTC" do
    @company.update_columns(time_zone: "Not/AZone")

    activity = @user.activities.new(started_at: Time.utc(2026, 10, 20, 23, 30))

    assert_equal Date.new(2026, 10, 20), DailyPointCap.day_range(activity).begin.to_date
  end
end
