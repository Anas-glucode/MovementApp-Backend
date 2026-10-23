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
end
