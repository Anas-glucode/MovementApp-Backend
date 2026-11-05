require "test_helper"
require "securerandom"

# Tests for badges: eligible-only counting, the automatic hook, streaks,
# personal records and the badge model rules.
class BadgesTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Badge Co", slug: "badge-co-test")
    @user = User.create!(company: @company, name: "Badger",
                         email: "badger-badges@example.com", password: "password123")
    @version = scoring_rule_versions(:one)

    # 08:00 UTC, ten days ago: safely in the past, and the company is on UTC
    @base = 10.days.ago.utc.beginning_of_day + 8.hours
  end

  # ---- helpers ----
  def build_badge(category:, criteria_type:, value:)
    Badge.create!(company: @company, name: "Badge #{SecureRandom.hex(3)}",
                  category: category, criteria_type: criteria_type,
                  criteria_value: value)
  end

  # Creates an activity directly (no scoring, no badge hook)
  def make_activity(started_at: @base, minutes: 20, status: "eligible", **attrs)
    @user.activities.create!(
      {
        activity_type: "walking", source: "manual", status: status,
        started_at: started_at, ended_at: started_at + minutes.minutes,
        duration_seconds: minutes * 60
      }.merge(attrs)
    )
  end

  def earned?(badge)
    UserBadge.exists?(user_id: @user.id, badge_id: badge.id)
  end

  def evaluate(activity = nil)
    BadgeEvaluationService.new(@user, activity).evaluate
  end

  # ---- only eligible activities count ----
  test "a cumulative badge counts eligible activities only" do
    badge = build_badge(category: "steps", criteria_type: "cumulative", value: 1000)
    make_activity(steps: 600)
    make_activity(started_at: @base + 1.hour, steps: 600, status: "rejected")
    make_activity(started_at: @base + 2.hour, steps: 600, status: "under_review")

    evaluate

    assert_not earned?(badge)

    make_activity(started_at: @base + 3.hours, steps: 600)
    evaluate

    assert earned?(badge)
  end

  test "a single-activity badge is not earned by an activity that is not eligible" do
    badge = build_badge(category: "steps", criteria_type: "single_activity", value: 10_000)
    activity = make_activity(steps: 12_000, status: "under_review")

    evaluate(activity)

    assert_not earned?(badge)
  end

  test "a single-activity badge is earned by an eligible activity and remembers which" do
    badge = build_badge(category: "steps", criteria_type: "single_activity", value: 10_000)
    activity = make_activity(steps: 12_000)

    evaluate(activity)

    assert earned?(badge)
    assert_equal activity.id, UserBadge.find_by(user_id: @user.id, badge_id: badge.id).activity_id
  end

  test "a milestone badge counts eligible activities" do
    badge = build_badge(category: "milestone", criteria_type: "single_activity", value: 2)
    make_activity(status: "rejected")
    first = make_activity(started_at: @base + 1.hour)

    evaluate(first)
    assert_not earned?(badge)

    second = make_activity(started_at: @base + 2.hours)
    evaluate(second)

    assert earned?(badge)
  end

  
# ---- badge notifications ----
test "earning a badge creates a notification" do
  badge = build_badge(
    category: "steps",
    criteria_type: "single_activity",
    value: 10_000
  )

  activity = make_activity(steps: 12_000)

  evaluate(activity)

  user_badge = UserBadge.find_by(user: @user, badge: badge)
  notification = Notification.find_by(
    user: @user,
    notification_type: "badge_earned"
  )

  assert user_badge.present?
  assert notification.present?
  assert_equal "New badge earned!", notification.title
  assert_includes notification.message, badge.name
  assert_equal "UserBadge", notification.notifiable_type
  assert_equal user_badge.id, notification.notifiable_id
  assert_equal badge.id, notification.data["badge_id"]
  assert_equal badge.name, notification.data["badge_name"]
  assert_nil notification.read_at
end

test "evaluating an already earned badge does not create duplicate notifications" do
  badge = build_badge(
    category: "steps",
    criteria_type: "single_activity",
    value: 10_000
  )

  activity = make_activity(steps: 12_000)

  evaluate(activity)
  first_notification_count = Notification.where(
    user: @user,
    notification_type: "badge_earned"
  ).count

  evaluate(activity)

  assert_equal 1, first_notification_count
  assert_equal first_notification_count,
               Notification.where(
                 user: @user,
                 notification_type: "badge_earned"
               ).count
end


  # ---- no double awards ----
  test "a badge is only ever awarded once" do
    badge = build_badge(category: "steps", criteria_type: "cumulative", value: 100)
    make_activity(steps: 500)

    evaluate
    evaluate

    assert_equal 1, UserBadge.where(user_id: @user.id, badge_id: badge.id).count
  end

  test "awarding a badge that is already earned does nothing instead of crashing" do
    badge = build_badge(category: "steps", criteria_type: "cumulative", value: 100)
    UserBadge.create!(user: @user, badge: badge)

    assert_nil BadgeEvaluationService.new(@user).send(:award_badge, badge)
  end

  # ---- the automatic hook ----
  test "logging an activity awards badges automatically" do
    badge = build_badge(category: "steps", criteria_type: "single_activity", value: 10_000)

    result = ActivityCreationService.call(
      user: @user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: 3.hours.ago,
        ended_at: 2.hours.ago,
        steps: 12_000,
        reported_intensity: 5
      }
    )

    assert result[:activity].present?, result[:errors].inspect
    assert earned?(badge)
  end

  test "a failure while checking badges never stops an activity being logged" do
    build_badge(category: "steps", criteria_type: "single_activity", value: 10)

    original_new = BadgeEvaluationService.method(:new)
    BadgeEvaluationService.define_singleton_method(:new) { |*_args| raise "boom" }

    result =
      ActivityCreationService.call(
        user: @user,
        source: "manual",
        attributes: {
          activity_type: "walking",
          started_at: 3.hours.ago,
          ended_at: 2.hours.ago,
          steps: 500,
          reported_intensity: 5
        }
      )
  ensure
    BadgeEvaluationService.define_singleton_method(:new, original_new) if original_new

    assert result[:activity].present?, result[:errors].inspect
    assert result[:activity].activity_point_award.present?
  end

  # ---- streaks ----
  test "days in a row make a streak and a gap breaks it" do
    [0, 1, 3].each { |day| make_activity(started_at: @base + day.days) }

    assert_equal 2, ActivityStreaks.call(user: @user)[:longest_daily]
  end

  test "a day only counts when there was enough activity" do
    [0, 1, 2].each { |day| make_activity(started_at: @base + day.days, minutes: 2) }

    streaks = ActivityStreaks.call(user: @user)

    assert_equal 0, streaks[:longest_daily]
    assert_equal 0, streaks[:active_days]
  end

  test "several short activities on one day add up to an active day" do
    make_activity(started_at: @base, minutes: 6)
    make_activity(started_at: @base + 2.hours, minutes: 6)

    assert_equal 1, ActivityStreaks.call(user: @user)[:active_days]
  end

  test "rejected activities do not extend a streak" do
    make_activity(started_at: @base)
    make_activity(started_at: @base + 1.day, status: "rejected")
    make_activity(started_at: @base + 2.days)

    assert_equal 1, ActivityStreaks.call(user: @user)[:longest_daily]
  end

  test "the current streak survives not having logged today yet" do
    yesterday = Time.current.utc.beginning_of_day - 1.day + 8.hours
    make_activity(started_at: yesterday - 1.day)
    make_activity(started_at: yesterday)

    assert_equal 2, ActivityStreaks.call(user: @user)[:current_daily]
  end

  test "the current streak is over once a whole day has been missed" do
    old = Time.current.utc.beginning_of_day - 3.days + 8.hours
    make_activity(started_at: old)

    assert_equal 0, ActivityStreaks.call(user: @user)[:current_daily]
  end

  test "weeks in a row make a weekly streak" do
    [0, 7, 14].each { |days| make_activity(started_at: @base + days.days) }

    assert_equal 3, ActivityStreaks.call(user: @user)[:longest_weekly]
  end

  test "a daily streak badge is earned when the streak is long enough" do
    badge = build_badge(category: "streak", criteria_type: "daily_streak", value: 3)
    [0, 1].each { |day| make_activity(started_at: @base + day.days) }

    evaluate
    assert_not earned?(badge)

    make_activity(started_at: @base + 2.days)
    evaluate

    assert earned?(badge)
  end

  # ---- personal records ----
  test "personal records ignore activities that are not eligible" do
    make_activity(steps: 3000, distance_meters: 2000)
    make_activity(started_at: @base + 3.hours, steps: 4000, distance_meters: 3000)
    make_activity(started_at: @base + 6.hours, steps: 9000, status: "rejected")

    records = PersonalRecords.call(user: @user)

    assert_equal 4000, records[:max_steps]
    assert_equal 7000, records[:max_steps_in_a_day]
  end

  test "longest run and ride are tracked per sport" do
    make_activity(activity_type: "running", distance_meters: 5000)
    make_activity(started_at: @base + 3.hours, activity_type: "running", distance_meters: 8000)
    make_activity(started_at: @base + 6.hours, activity_type: "running", distance_meters: 20_000, status: "rejected")
    make_activity(started_at: @base + 9.hours, activity_type: "cycling", distance_meters: 12_000)

    records = PersonalRecords.call(user: @user)

    assert_equal 8000.0, records[:longest_run_meters]
    assert_equal 12_000.0, records[:longest_cycling_meters]
  end

  test "points records add up awards per day and per week" do
    first = make_activity
    second = make_activity(started_at: @base + 3.hours)
    ActivityPointAward.create!(activity: first, scoring_rule_version: @version, points: 40)
    ActivityPointAward.create!(activity: second, scoring_rule_version: @version, points: 30)

    records = PersonalRecords.call(user: @user)

    assert_equal 70, records[:max_points_in_a_day]
    assert_equal 70, records[:max_points_in_a_week]
  end

  test "a person with no activities has zero records, not errors" do
    records = PersonalRecords.call(user: @user)

    assert_equal 0, records[:max_steps_in_a_day]
    assert_equal 0.0, records[:longest_run_meters]
    assert_equal 0, records[:longest_streak_days]
  end

  # ---- the badge model ----
  test "a category that does not fit the criteria type is refused" do
    badge = Badge.new(company: @company, name: "Odd one", category: "steps",
                      criteria_type: "daily_streak", criteria_value: 3)

    assert_not badge.valid?
  end

  test "a badge target cannot change once someone has earned it" do
    badge = build_badge(category: "steps", criteria_type: "cumulative", value: 100)
    UserBadge.create!(user: @user, badge: badge)

    assert_not badge.update(criteria_value: 5000)
    assert badge.reload.update(description: "A clearer description")
  end

  test "a badge someone has earned cannot be deleted" do
    badge = build_badge(category: "steps", criteria_type: "cumulative", value: 100)
    UserBadge.create!(user: @user, badge: badge)

    assert_not badge.destroy
  end
end
