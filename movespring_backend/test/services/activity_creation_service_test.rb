require "test_helper"

class ActivityCreationServiceTest < ActiveSupport::TestCase
  test "holds a normal manual activity for review without awarding points" do
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
    activity = result[:activity]

    assert_equal "manual", activity.source
    assert_equal "under_review", activity.status
    assert_equal "Manual activity requires review", activity.review_reason
    assert_equal 1800, activity.duration_seconds
    assert_nil activity.activity_point_award
    assert_equal 0, ChallengeActivityAward.where(activity_id: activity.id).count
  end

  test "holds an old manual activity for review without awarding points" do
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

    activity = result[:activity]

    assert_equal "under_review", activity.status
    assert_equal "Manual activity requires review", activity.review_reason
    assert_nil activity.activity_point_award
  end

  test "keeps an imported Health Connect workout pending without awarding points" do
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

    activity = result[:activity]

    assert_equal "pending", activity.status
    assert_nil activity.activity_point_award
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

  test "accepts manual activity for review when no published scoring rules exist" do
    user = users(:one)

    ScoringRuleVersion.update_all(status: "draft", published_at: nil)

    result = ActivityCreationService.call(
      user: user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: 1.hour.ago,
        ended_at: 30.minutes.ago
      }
    )

    assert result[:activity].present?, result[:errors].inspect
    assert_equal "under_review", result[:activity].status
    assert_nil result[:activity].activity_point_award
  end
end