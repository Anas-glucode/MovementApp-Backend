require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  test "valid activity fixture is valid" do
    assert_predicate activities(:one), :valid?
  end

  test "requires an activity type" do
    activity = activities(:one)
    activity.activity_type = nil

    assert_not activity.valid?
    assert_includes activity.errors[:activity_type], "can't be blank"
  end

  test "rejects unsupported sources" do
    activity = activities(:one)
    activity.source = "unknown"

    assert_not activity.valid?
    assert_includes activity.errors[:source], "is not included in the list"
  end

  test "rejects unsupported statuses" do
    activity = activities(:one)
    activity.status = "approved"

    assert_not activity.valid?
    assert_includes activity.errors[:status], "is not included in the list"
  end

  test "requires a positive duration" do
    activity = activities(:one)
    activity.duration_seconds = 0

    assert_not activity.valid?
    assert activity.errors[:duration_seconds].any?
  end

  test "requires the end time to be after the start time" do
    activity = activities(:one)
    activity.ended_at = activity.started_at

    assert_not activity.valid?
    assert activity.errors[:ended_at].any?
  end

  test "rejects negative steps" do
    activity = activities(:one)
    activity.steps = -1

    assert_not activity.valid?
    assert activity.errors[:steps].any?
  end

  test "rejects negative distance" do
    activity = activities(:one)
    activity.distance_meters = -1

    assert_not activity.valid?
    assert activity.errors[:distance_meters].any?
  end

  test "rejects reported intensity outside 1 to 10" do
    activity = activities(:one)
    activity.reported_intensity = 11

    assert_not activity.valid?
    assert activity.errors[:reported_intensity].any?
  end

  test "allows optional distance and heart rate to be absent" do
    activity = activities(:one)
    activity.distance_meters = nil
    activity.average_heart_rate = nil

    assert_predicate activity, :valid?
  end

  test "rejects duplicate provider record IDs for the same user and source" do
    original = activities(:one)
    duplicate = original.dup

    assert_not duplicate.valid?
    assert duplicate.errors[:source_record_id].any?
  end

  test "allows the same provider record ID for a different user" do
    original = activities(:one)
    other_user_activity = original.dup
    other_user_activity.user = users(:two)

    assert_predicate other_user_activity, :valid?
  end
end
