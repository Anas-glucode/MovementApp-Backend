
require "test_helper"

class ActivityPointAwardTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Award Callback Co",
      slug: "award-callback-co-test",
      time_zone: "Africa/Johannesburg"
    )

    @user = User.create!(
      company: @company,
      name: "Award Callback Tester",
      email: "award-callback@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: "employee",
      status: "active"
    )

    @version = scoring_rule_versions(:one)
  end

  test "automatically creates personal record events when points are awarded" do
    activity = create_activity(
      activity_type: "running",
      distance_meters: 5_000,
      duration_seconds: 1_800,
      steps: 6_000
    )

    award = ActivityPointAward.create!(
      activity: activity,
      scoring_rule_version: @version,
      points: 50
    )

    event = PersonalRecordEvent.find_by(
      user: @user,
      activity: activity,
      record_type: "longest_run"
    )

    assert award.persisted?
    assert_not_nil event
    assert_equal 5_000, event.new_value.to_f
  end

  test "does not create personal record events for pending activities" do
    activity = create_activity(
      activity_type: "running",
      distance_meters: 5_000,
      duration_seconds: 1_800,
      steps: 6_000,
      status: "pending"
    )

    ActivityPointAward.create!(
      activity: activity,
      scoring_rule_version: @version,
      points: 50
    )

    assert_empty PersonalRecordEvent.where(
      user: @user,
      activity: activity
    )
  end

  private

  def create_activity(activity_type:, distance_meters:, duration_seconds:,
                      steps:, status: "eligible")
    started_at = Time.zone.local(2026, 10, 30, 8, 0)

    @user.activities.create!(
      activity_type: activity_type,
      source: "manual",
      status: status,
      started_at: started_at,
      ended_at: started_at + duration_seconds,
      duration_seconds: duration_seconds,
      distance_meters: distance_meters,
      steps: steps,
      active_calories: 100
    )
  end
end
