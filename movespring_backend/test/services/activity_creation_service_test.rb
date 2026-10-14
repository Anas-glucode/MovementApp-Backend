require "test_helper"

class ActivityCreationServiceTest < ActiveSupport::TestCase
  test "accepts a normal manual activity as eligible" do
    user = users(:one)
    started_at = 1.hour.ago

    result = ActivityCreationService.call(
      user: user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: started_at,
        ended_at: started_at + 30.minutes,
        distance_meters: 2000
      }
    )

    assert result[:activity].present?, result[:errors].inspect
    assert_equal "manual", result[:activity].source
    assert_equal "eligible", result[:activity].status
    assert_equal 1800, result[:activity].duration_seconds
  end

  test "holds an old manual activity for review" do
    user = users(:one)
    started_at = 31.days.ago

    result = ActivityCreationService.call(
      user: user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: started_at,
        ended_at: started_at + 30.minutes
      }
    )

    assert result[:activity].present?, result[:errors].inspect
    assert_equal "under_review", result[:activity].status
    assert_equal "Manual activity requires review",
                 result[:activity].review_reason
  end

  test "keeps an imported Health Connect workout pending" do
    user = users(:one)
    started_at = 2.hours.ago

    result = ActivityCreationService.call(
      user: user,
      source: "health_connect",
      attributes: {
        activity_type: "running",
        source_record_id: "test-import-#{SecureRandom.uuid}",
        started_at: started_at,
        ended_at: started_at + 30.minutes,
        duration_seconds: 1800,
        distance_meters: 5000
      }
    )

    assert result[:activity].present?, result[:errors].inspect
    assert_equal "pending", result[:activity].status
  end

  test "rejects an imported workout with a mismatched duration" do
    user = users(:one)
    started_at = 2.hours.ago

    result = ActivityCreationService.call(
      user: user,
      source: "health_connect",
      attributes: {
        activity_type: "running",
        source_record_id: "bad-import-#{SecureRandom.uuid}",
        started_at: started_at,
        ended_at: started_at + 30.minutes,
        duration_seconds: 600
      }
    )

    assert result[:errors].present?
    assert_includes result[:errors],
                    "Reported duration does not match the activity times"
  end
end
