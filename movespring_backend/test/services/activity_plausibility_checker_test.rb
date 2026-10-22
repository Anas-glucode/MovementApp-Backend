require "test_helper"

class ActivityPlausibilityCheckerTest < ActiveSupport::TestCase
  test "returns nil for plausible activity data without saving" do
    activity = Activity.new(
      activity_type: "running",
      duration_seconds: 1_200,
      distance_meters: 5_000,
      steps: 3_000,
      active_calories: 500,
      average_heart_rate: 120
    )

    assert_nil ActivityPlausibilityChecker.call(activity: activity)
    assert_not activity.persisted?
  end

  test "flags an implausible heart rate" do
    activity = Activity.new(duration_seconds: 600, average_heart_rate: 20)

    assert_equal "Heart rate looks implausible",
                 ActivityPlausibilityChecker.call(activity: activity)
  end

  test "flags implausible distance, steps, and calories" do
    fast_activity = Activity.new(
      activity_type: "running",
      duration_seconds: 600,
      distance_meters: 5_000
    )
    high_step_activity = Activity.new(duration_seconds: 600, steps: 2_501)
    high_calorie_activity = Activity.new(duration_seconds: 600, active_calories: 401)

    assert_equal "Distance is too large for the time taken",
                 ActivityPlausibilityChecker.call(activity: fast_activity)
    assert_equal "Step count is too high for the time taken",
                 ActivityPlausibilityChecker.call(activity: high_step_activity)
    assert_equal "Calories are too high for the time taken",
                 ActivityPlausibilityChecker.call(activity: high_calorie_activity)
  end
end
