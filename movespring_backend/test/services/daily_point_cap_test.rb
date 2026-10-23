require "test_helper"
require "securerandom"

class DailyPointCapTest < ActiveSupport::TestCase
  setup do
    # A copy of the standard test rules with a small cap of 40 points a day
    @capped_rules = ScoringRuleVersion.create!(
      name: "Capped Test Rules",
      version_number: 97,
      status: "published",
      published_at: Time.current,
      rules: scoring_rule_versions(:one).rules.deep_dup.merge("daily_point_cap" => 40)
    )

    @user = users(:one)

    # A day with nothing else on it in the fixtures
    @day = Time.utc(2026, 9, 1, 8, 0)
  end

  # Saves a real, eligible walking activity (1 point per minute at baseline)
  def create_walk(user:, started_at:, minutes: 30, time_zone: "UTC")
    Activity.create!(
      user: user,
      activity_type: "walking",
      source: "manual",
      started_at: started_at,
      ended_at: started_at + minutes.minutes,
      duration_seconds: minutes * 60,
      status: "eligible",
      time_zone: time_zone
    )
  end

  test "personal points stop at the daily cap" do
    awards = 3.times.map do |i|
      activity = create_walk(user: @user, started_at: @day + (i * 2).hours)

      ActivityScoringService.call(
        activity: activity,
        scoring_rule_version: @capped_rules
      )
    end

    # 30 earned, then only 10 left of the 40, then nothing left
    assert_equal [30, 10, 0], awards.map(&:points)
  end

  test "a new day starts with a fresh allowance" do
    2.times do |i|
      activity = create_walk(user: @user, started_at: @day + (i * 2).hours)
      ActivityScoringService.call(
        activity: activity,
        scoring_rule_version: @capped_rules
      )
    end

    next_day = create_walk(user: @user, started_at: @day + 1.day)
    award = ActivityScoringService.call(
      activity: next_day,
      scoring_rule_version: @capped_rules
    )

    assert_equal 30, award.points
  end

  test "uses the default cap of 500 when the rules do not set one" do
    # Twenty hours of walking would be 1200 points without a cap
    marathon = create_walk(user: @user, started_at: @day, minutes: 1200)

    award = ActivityScoringService.call(
      activity: marathon,
      scoring_rule_version: scoring_rule_versions(:one)
    )

    assert_equal DailyPointCap::DEFAULT_CAP, award.points
  end

  test "days are judged in the activity's own time zone" do
    # In UTC these are the same day. In Johannesburg (2 hours ahead) the first
    # is 23:30 on 1 September and the second is 00:30 on 2 September,
    # so they belong to different days and each gets a full allowance.
    first = create_walk(
      user: @user,
      started_at: Time.utc(2026, 9, 1, 21, 30),
      time_zone: "Africa/Johannesburg"
    )
    second = create_walk(
      user: @user,
      started_at: Time.utc(2026, 9, 1, 22, 30),
      time_zone: "Africa/Johannesburg"
    )

    awards = [first, second].map do |activity|
      ActivityScoringService.call(
        activity: activity,
        scoring_rule_version: @capped_rules
      )
    end

    assert_equal [30, 10], awards.map(&:points)
  end

  test "challenge points stop at the daily cap too" do
    company = Company.create!(
      name: "Cap Co",
      slug: "cap-co-#{SecureRandom.hex(4)}",
      status: "active"
    )

    employee = User.create!(
      company: company,
      name: "Cap Tester",
      email: "cap-#{SecureRandom.hex(6)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: "employee",
      status: "active"
    )

    # People can only join a challenge that is published and has not started,
    # so create it that way first...
    challenge = Challenge.create!(
      company: company,
      scoring_rule_version: @capped_rules,
      name: "Cap Challenge",
      starts_at: 1.day.from_now,
      ends_at: 10.days.from_now,
      status: "published"
    )

    ChallengeParticipation.create!(challenge: challenge, user: employee)

    # ...then, once the employee has joined, move the challenge to the
    # September window where our test activities happened and mark it active.
    # update_columns skips the validations, which is fine for test setup.
    challenge.update_columns(
      status: "active",
      starts_at: Time.utc(2026, 8, 30),
      ends_at: Time.utc(2026, 9, 5)
    )

    awards = 3.times.map do |i|
      activity = create_walk(user: employee, started_at: @day + (i * 2).hours)

      ChallengeActivityScoringService.call(
        challenge: challenge,
        activity: activity
      )
    end

    assert_equal [30, 10, 0], awards.map(&:points)
  end
end
