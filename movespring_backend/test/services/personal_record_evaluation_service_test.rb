
require "test_helper"

class PersonalRecordEvaluationServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Evaluation Co",
      slug: "evaluation-co-test",
      time_zone: "Africa/Johannesburg"
    )

    @user = User.create!(
      company: @company,
      name: "Evaluation Tester",
      email: "evaluation-tester@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: "employee",
      status: "active"
    )

    @version = scoring_rule_versions(:one)
  end

  test "creates an event when an activity establishes a longest run" do
    activity = create_activity(
      activity_type: "running",
      distance_meters: 5_000,
      duration_seconds: 1_800,
      steps: 6_000
    )

    create_point_award(activity, 50)

    PersonalRecordEvaluationService.call(activity: activity)

    event = PersonalRecordEvent.find_by!(
      user: @user,
      activity: activity,
      record_type: "longest_run"
    )

    assert_nil event.previous_value
    assert_equal 5_000, event.new_value.to_f
  end

  test "does not create a longest run event when the activity is shorter" do
    previous_run = create_activity(
      activity_type: "running",
      distance_meters: 8_000,
      duration_seconds: 2_400,
      steps: 8_000
    )

    create_point_award(previous_run, 50)

    # Evaluate the previous activity first so its records are established.
    PersonalRecordEvaluationService.call(activity: previous_run)

    new_run = create_activity(
      activity_type: "running",
      distance_meters: 5_000,
      duration_seconds: 1_500,
      steps: 5_000
    )

    create_point_award(new_run, 30)

    PersonalRecordEvaluationService.call(activity: new_run)

    assert_nil PersonalRecordEvent.find_by(
      user: @user,
      activity: new_run,
      record_type: "longest_run"
    )
  end

  test "does not evaluate activities that are not eligible" do
    activity = create_activity(
      activity_type: "running",
      distance_meters: 5_000,
      duration_seconds: 1_800,
      steps: 6_000,
      status: "pending"
    )

    create_point_award(activity, 50)

    assert_no_difference "PersonalRecordEvent.count" do
      PersonalRecordEvaluationService.call(activity: activity)
    end
  end

  test "does not create duplicate events when evaluated twice" do
    activity = create_activity(
      activity_type: "running",
      distance_meters: 5_000,
      duration_seconds: 1_800,
      steps: 6_000
    )

    create_point_award(activity, 50)

    PersonalRecordEvaluationService.call(activity: activity)

    assert_no_difference "PersonalRecordEvent.count" do
      PersonalRecordEvaluationService.call(activity: activity)
    end
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

  def create_point_award(activity, points)
    ActivityPointAward.create!(
      activity: activity,
      scoring_rule_version: @version,
      points: points
    )
  end
end
