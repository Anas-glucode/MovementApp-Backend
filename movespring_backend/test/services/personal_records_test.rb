require "test_helper"

class PersonalRecordsTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Records Co",
      slug: "records-co-test",
      time_zone: "Africa/Johannesburg"
    )
    @user = User.create!(
      company: @company,
      name: "Records Tester",
      email: "records-tester@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: "employee",
      status: "active"
    )
    @version = scoring_rule_versions(:one)
  end

  test "returns eligible activity, local-day, points and streak records" do
    travel_to Time.utc(2026, 10, 22, 12) do
      run = create_activity(
        started_at: Time.utc(2026, 10, 21, 18),
        activity_type: "running",
        steps: 1_000,
        distance_meters: 1_200.5,
        duration_seconds: 600,
        active_calories: 80.5
      )
      cycle = create_activity(
        started_at: Time.utc(2026, 10, 21, 19),
        activity_type: "cycling",
        steps: 2_000,
        distance_meters: 2_500.5,
        duration_seconds: 600,
        active_calories: 100.5
      )
      next_day = create_activity(
        started_at: Time.utc(2026, 10, 22, 8),
        activity_type: "walking",
        steps: 500,
        distance_meters: 300,
        duration_seconds: 600,
        active_calories: 30
      )
      pending = create_activity(
        started_at: Time.utc(2026, 10, 22, 9),
        activity_type: "running",
        steps: 50_000,
        distance_meters: 99_000,
        duration_seconds: 3_600,
        active_calories: 5_000,
        status: "pending"
      )

      create_point_award(run, 30)
      create_point_award(cycle, 40)
      create_point_award(next_day, 10)
      create_point_award(pending, 1_000)

      records = PersonalRecords.call(user: @user)

      assert_equal 2_000, records[:max_steps]
      assert_equal 2_500.5, records[:max_distance_meters]
      assert_equal 600, records[:max_duration_seconds]
      assert_equal 100.5, records[:max_active_calories]
      assert_equal 3_000, records[:max_steps_in_a_day]
      assert_equal 1_200, records[:max_active_seconds_in_a_day]
      assert_equal 1_200.5, records[:longest_run_meters]
      assert_equal 2_500.5, records[:longest_cycling_meters]
      assert_equal 70, records[:max_points_in_a_day]
      assert_equal 80, records[:max_points_in_a_week]
      assert_equal 2, records[:longest_streak_days]
      assert_equal 2, records[:current_streak_days]
      assert_equal 1, records[:longest_weekly_streak]
      assert_equal 2, records[:active_days]
      assert_kind_of Float, records[:max_distance_meters]
      assert_kind_of Float, records[:max_active_calories]
    end
  end

  test "returns zero for records when there are no eligible activities" do
    records = PersonalRecords.call(user: @user)

    assert_equal 0, records[:max_steps]
    assert_equal 0.0, records[:max_distance_meters]
    assert_equal 0, records[:max_duration_seconds]
    assert_equal 0.0, records[:max_active_calories]
    assert_equal 0, records[:max_points_in_a_week]
    assert_equal 0, records[:active_days]
  end

  test "excludes the selected activity from point totals" do
    included = create_activity(
      started_at: Time.utc(2026, 10, 21, 18),
      activity_type: "walking",
      steps: 1_000,
      distance_meters: 500,
      duration_seconds: 600,
      active_calories: 50
    )
    excluded = create_activity(
      started_at: Time.utc(2026, 10, 21, 19),
      activity_type: "walking",
      steps: 2_000,
      distance_meters: 1_000,
      duration_seconds: 600,
      active_calories: 100
    )
    create_point_award(included, 30)
    create_point_award(excluded, 40)

    records = PersonalRecords.call(user: @user, excluding_activity_id: excluded.id)

    assert_equal 30, records[:max_points_in_a_day]
    assert_equal 30, records[:max_points_in_a_week]
  end

  private

  def create_activity(started_at:, activity_type:, steps:, distance_meters:,
                      duration_seconds:, active_calories:, status: "eligible")
    @user.activities.create!(
      activity_type: activity_type,
      source: "manual",
      status: status,
      started_at: started_at,
      ended_at: started_at + duration_seconds,
      steps: steps,
      distance_meters: distance_meters,
      duration_seconds: duration_seconds,
      active_calories: active_calories
    )
  end

  def create_point_award(activity, points)
    ActivityPointAward.create!(
      activity: activity,
      scoring_rule_version: @version,
      points: points
    )
  end
end
