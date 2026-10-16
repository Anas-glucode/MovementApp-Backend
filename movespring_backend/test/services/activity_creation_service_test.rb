require "test_helper"

class ActivityCreationServiceTest < ActiveSupport::TestCase
  test "accepts a normal manual activity as eligible and awards points once" do
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
    # A normal manual walk is trusted: eligible, no review reason, scored at once
    assert_equal "eligible", activity.status
    assert_nil activity.review_reason
    assert_equal 1800, activity.duration_seconds

    award = activity.activity_point_award
    assert award.present?, "Expected an eligible activity to receive a point award"
    assert_operator award.points, :>, 0

    # Scoring the same activity again must not create a second award
    assert_no_difference("ActivityPointAward.count") do
      repeated_award = ActivityScoringService.call(
        activity: activity,
        scoring_rule_version: award.scoring_rule_version
      )

      assert_equal award.id, repeated_award.id
    end
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

  test "rolls back activity creation when no published scoring rules exist" do
    user = users(:one)

    # Unpublish every scoring rule set, so a normal activity cannot be scored
    ScoringRuleVersion.update_all(status: "draft", published_at: nil)

    # The activity must NOT be saved half-finished: no points, no activity
    assert_no_difference("Activity.count") do
      result = ActivityCreationService.call(
        user: user,
        source: "manual",
        attributes: {
          activity_type: "walking",
          started_at: 1.hour.ago,
          ended_at: 30.minutes.ago
        }
      )

      assert_includes result[:errors],
                      "No published scoring rules are available"
    end
  end

  test "holds a manual activity that overlaps an earlier one for review" do
    user = users(:one)
    started_at = 3.hours.ago

    # The first walk is normal, so it is accepted and scored
    first = ActivityCreationService.call(
      user: user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: started_at,
        ended_at: started_at + 30.minutes
      }
    )
    assert first[:activity].present?, first[:errors].inspect
    assert first[:activity].activity_point_award.present?

    # The second walk starts 10 minutes into the first one, so the times overlap
    second = ActivityCreationService.call(
      user: user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: started_at + 10.minutes,
        ended_at: started_at + 40.minutes
      }
    )
    assert second[:activity].present?, second[:errors].inspect

    # It is saved, but held for an admin and earns no points yet
    assert_equal "under_review", second[:activity].status
    assert_equal "Overlaps another activity", second[:activity].review_reason
    assert_nil second[:activity].activity_point_award
  end

  test "accepts back-to-back manual activities that do not overlap" do
    user = users(:one)
    started_at = 4.hours.ago

    first = ActivityCreationService.call(
      user: user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: started_at,
        ended_at: started_at + 30.minutes
      }
    )
    assert first[:activity].present?, first[:errors].inspect

    # The second walk starts at the exact moment the first one ended
    second = ActivityCreationService.call(
      user: user,
      source: "manual",
      attributes: {
        activity_type: "running",
        started_at: started_at + 30.minutes,
        ended_at: started_at + 60.minutes
      }
    )
    assert second[:activity].present?, second[:errors].inspect

    assert_equal "eligible", second[:activity].status
    assert second[:activity].activity_point_award.present?
  end

  test "a rejected activity does not block a new one in the same time window" do
    user = users(:one)
    started_at = 5.hours.ago

    first = ActivityCreationService.call(
      user: user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: started_at,
        ended_at: started_at + 30.minutes
      }
    )
    assert first[:activity].present?, first[:errors].inspect

    # Pretend an admin rejected the first one
    first[:activity].update_column(:status, "rejected")

    second = ActivityCreationService.call(
      user: user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: started_at,
        ended_at: started_at + 30.minutes
      }
    )
    assert second[:activity].present?, second[:errors].inspect

    assert_equal "eligible", second[:activity].status
  end

  test "holds a manual activity that ends in the future for review" do
    user = users(:one)

    # Starts a minute ago but claims to run for another two hours
    result = ActivityCreationService.call(
      user: user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: 1.minute.ago,
        ended_at: 2.hours.from_now
      }
    )
    assert result[:activity].present?, result[:errors].inspect

    assert_equal "under_review", result[:activity].status
    assert_nil result[:activity].activity_point_award
  end

  test "ignores a client-supplied heart rate and intensity source on manual entries" do
    user = users(:one)
    started_at = 6.hours.ago

    # The client claims a measured heart rate, which a manual entry cannot have
    result = ActivityCreationService.call(
      user: user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: started_at,
        ended_at: started_at + 30.minutes,
        average_heart_rate: 190,
        intensity_source: "heart_rate",
        reported_intensity: 7
      }
    )
    assert result[:activity].present?, result[:errors].inspect

    activity = result[:activity]

    # The claimed heart rate is dropped, and the server labels the effort score
    assert_nil activity.average_heart_rate
    assert_equal "self_reported", activity.intensity_source
    assert_equal 7, activity.reported_intensity
  end

  test "a manual entry with no effort score has no intensity source" do
    user = users(:one)
    started_at = 7.hours.ago

    result = ActivityCreationService.call(
      user: user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: started_at,
        ended_at: started_at + 30.minutes,
        intensity_source: "heart_rate"
      }
    )
    assert result[:activity].present?, result[:errors].inspect

    # Even though the client sent "heart_rate", the server ignores it
    assert_nil result[:activity].intensity_source
  end
end
