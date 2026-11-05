require "test_helper"
require "securerandom"

class ActivityReviewServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Review Co",
      slug: "review-co-#{SecureRandom.hex(4)}",
      status: "active"
    )

    @admin = create_user(role: "company_admin")
    @employee = create_user(role: "employee")
  end

  # Creates a user in the test company
  def create_user(role:)
    User.create!(
      company: @company,
      name: "Test #{role.humanize}",
      email: "review-#{SecureRandom.hex(6)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: role,
      status: "active"
    )
  end

  # Creates an activity waiting for review, owned by the given user
  def create_waiting_activity(owner)
    started_at = 2.hours.ago

    Activity.create!(
      user: owner,
      activity_type: "walking",
      source: "manual",
      started_at: started_at,
      ended_at: started_at + 30.minutes,
      duration_seconds: 1800,
      status: "under_review",
      review_reason: "Manual activity requires review"
    )
  end

  test "an admin can approve an employee's activity" do
    activity = create_waiting_activity(@employee)

    review = ActivityReviewService.call(
      activity: activity,
      reviewer: @admin,
      decision: "approved"
    )

    assert_equal "approved", review.decision
    assert_equal "eligible", activity.reload.status
    assert activity.activity_point_award.present?
  end

  test "an admin cannot approve their own activity" do
    activity = create_waiting_activity(@admin)

    error = assert_raises(ActivityReviewService::ReviewError) do
      ActivityReviewService.call(
        activity: activity,
        reviewer: @admin,
        decision: "approved"
      )
    end

    assert_equal "You cannot review your own activity", error.message

    # Nothing changed: still waiting, no review recorded, no points
    assert_equal "under_review", activity.reload.status
    assert_equal 0, ActivityReview.where(activity_id: activity.id).count
    assert_nil activity.activity_point_award
  end

  test "an admin cannot reject their own activity either" do
    activity = create_waiting_activity(@admin)

    assert_raises(ActivityReviewService::ReviewError) do
      ActivityReviewService.call(
        activity: activity,
        reviewer: @admin,
        decision: "rejected",
        reason: "Changed my mind"
      )
    end

    assert_equal "under_review", activity.reload.status
    assert_equal 0, ActivityReview.where(activity_id: activity.id).count
  end

  test "an activity with a point award cannot be reviewed" do
    activity = create_waiting_activity(@employee)
    ActivityPointAward.create!(
      activity: activity,
      scoring_rule_version: scoring_rule_versions(:one),
      points: 10
    )

    error = assert_raises(ActivityReviewService::ReviewError) do
      ActivityReviewService.call(
        activity: activity,
        reviewer: @admin,
        decision: "rejected",
        reason: "Needs correction"
      )
    end

    assert_equal "This activity already has points and cannot be reviewed",
                 error.message
    assert_equal "under_review", activity.reload.status
    assert_equal 0, ActivityReview.where(activity_id: activity.id).count
  end

  test "an activity with a challenge award cannot be reviewed" do
    activity = create_waiting_activity(@employee)
    scoring_rules = scoring_rule_versions(:one)
    challenge = Challenge.create!(
      company: @company,
      scoring_rule_version: scoring_rules,
      name: "Review challenge",
      starts_at: 1.day.ago,
      ends_at: 1.day.from_now,
      status: "active"
    )
    ChallengeActivityAward.create!(
      challenge: challenge,
      activity: activity,
      scoring_rule_version: scoring_rules,
      points: 10
    )

    error = assert_raises(ActivityReviewService::ReviewError) do
      ActivityReviewService.call(
        activity: activity,
        reviewer: @admin,
        decision: "rejected",
        reason: "Needs correction"
      )
    end

    assert_equal "This activity already has points and cannot be reviewed",
                 error.message
    assert_equal "under_review", activity.reload.status
    assert_equal 0, ActivityReview.where(activity_id: activity.id).count
  end

    test "approving an activity creates an approval notification for the employee" do
    activity = create_waiting_activity(@employee)

    review = ActivityReviewService.call(
      activity: activity,
      reviewer: @admin,
      decision: "approved"
    )

    notification = @employee.notifications.find_by!(
      notification_type: "activity_approved",
      notifiable: review
    )

    assert_equal "Activity approved!", notification.title
    assert_includes notification.message, "walking"
    assert_equal activity.id, notification.data["activity_id"]
    assert_equal review.id, notification.data["review_id"]
    assert_equal "approved", notification.data["decision"]
    assert_nil notification.read_at

    assert_equal 0, @admin.notifications.where(
      notification_type: "activity_approved"
    ).count
  end

    test "rejecting an activity creates a rejection notification with the reason" do
    activity = create_waiting_activity(@employee)
    reason = "Activity details could not be verified"

    review = ActivityReviewService.call(
      activity: activity,
      reviewer: @admin,
      decision: "rejected",
      reason: reason
    )

    notification = @employee.notifications.find_by!(
      notification_type: "activity_rejected",
      notifiable: review
    )

    assert_equal "Activity rejected", notification.title
    assert_includes notification.message, reason
    assert_equal activity.id, notification.data["activity_id"]
    assert_equal review.id, notification.data["review_id"]
    assert_equal "rejected", notification.data["decision"]
    assert_equal reason, notification.data["reason"]
    assert_nil notification.read_at
  end

    test "failed review does not create a notification" do
    activity = create_waiting_activity(@admin)

    assert_raises(ActivityReviewService::ReviewError) do
      ActivityReviewService.call(
        activity: activity,
        reviewer: @admin,
        decision: "approved"
      )
    end

    assert_equal 0, @admin.notifications.count
  end

  test "notification failure does not undo a successful approval" do
  activity = create_waiting_activity(@employee)

  original_call = NotificationCreationService.method(:call)

  NotificationCreationService.define_singleton_method(:call) do |**_args|
    raise StandardError, "Notification service unavailable"
  end

  begin
    review = ActivityReviewService.call(
      activity: activity,
      reviewer: @admin,
      decision: "approved"
    )

    assert_equal "approved", review.decision
    assert_equal "eligible", activity.reload.status
    assert activity.activity_point_award.present?
  ensure
    NotificationCreationService.define_singleton_method(:call, original_call)
  end
end

end
