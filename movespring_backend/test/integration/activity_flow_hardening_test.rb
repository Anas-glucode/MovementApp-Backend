require "test_helper"

# Tests for the activity-flow hardening changes.
# Assumes the fixture scoring_rule_versions(:one) from your test suite
# (published, all sports, bands 3/6, no manual_multiplier).
class ActivityFlowHardeningTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Acme", slug: "acme-hardening")
    @user = User.create!(company: @company, name: "Employee",
                         email: "employee-hardening@example.com",
                         password: "password123")
    @admin = User.create!(company: @company, name: "Boss",
                          email: "boss-hardening@example.com",
                          password: "password123", role: "company_admin")

    # 06:00 UTC two days ago: safely in the past and inside the 30-day window.
    @base = 2.days.ago.utc.change(hour: 6, min: 0)
  end

  # ---- helpers ----
  def log_manual(offset_minutes: 0, minutes: 30, **extra)
    start = @base + offset_minutes.minutes

    ActivityCreationService.call(
      user: @user,
      source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: start.iso8601,
        ended_at: (start + minutes.minutes).iso8601,
        reported_intensity: 5,
        time_zone: "UTC"
      }.merge(extra)
    )
  end

  def publish_rules(extra = {})
    ScoringRuleVersion.create!(
      name: "Test v2",
      version_number: 50,
      status: "published",
      published_at: Time.current,
      rules: scoring_rule_versions(:one).rules.merge(extra)
    )
  end

  # ---- manual entries: policy ----
  test "manual activities earn a discounted amount when the rules say so" do
    publish_rules("manual_multiplier" => 0.5)

    activity = log_manual[:activity]

    # 30 min x walking 1.0 x moderate 1.0 = 30, halved for manual = 15
    assert_equal "eligible", activity.status
    assert_equal 15, activity.activity_point_award.points
  end

  test "manual entries need an effort level" do
    result = log_manual(reported_intensity: nil)

    assert_nil result[:activity]
    assert_match(/Effort level/, result[:errors].first)
  end

  test "a sixth manual activity on the same day is refused" do
    5.times { |i| assert log_manual(offset_minutes: i * 60)[:activity] }

    sixth = log_manual(offset_minutes: 5 * 60)

    assert_nil sixth[:activity]
    assert_match(/at most/, sixth[:errors].first)
  end

  # ---- input checks ----
  test "an activity that ends in the future is refused" do
    result = ActivityCreationService.call(
      user: @user, source: "manual",
      attributes: {
        activity_type: "walking",
        started_at: 10.minutes.ago.iso8601,
        ended_at: 2.hours.from_now.iso8601,
        reported_intensity: 5
      }
    )

    assert_nil result[:activity]
    assert_includes result[:errors].first, "future"
  end

  test "times without a UTC offset are refused instead of guessed" do
    result = log_manual(started_at: "2026-10-19T06:00:00",
                        ended_at: "2026-10-19T06:30:00")

    assert_nil result[:activity]
    assert_match(/UTC offset/, result[:errors].first)
  end

  test "an unknown activity type is refused" do
    result = log_manual(activity_type: "chess")

    assert_nil result[:activity]
    assert_equal ["Unsupported activity type"], result[:errors]
  end

  # ---- duplicates and overlaps ----
  test "logging the exact same activity twice is refused" do
    assert log_manual[:activity]

    second = log_manual

    assert_nil second[:activity]
    assert_match(/already been logged/, second[:errors].first)
  end

  test "an overlapping manual activity goes to review" do
    log_manual

    second = log_manual(offset_minutes: 15)[:activity]

    assert_equal "under_review", second.status
    assert_equal "Overlaps another activity", second.review_reason
  end

  # ---- failure paths ----
  test "when scoring fails nothing is left behind" do
    ScoringRuleVersion.update_all(status: "retired")

    assert_no_difference ["Activity.count", "ActivityPointAward.count"] do
      result = log_manual

      assert_nil result[:activity]
      assert_match(/No published scoring rules/, result[:errors].first)
    end
  end

  test "an activity that already has points cannot be reviewed" do
    activity = log_manual[:activity]
    assert activity.activity_point_award.present?

    # Force the "impossible" state: awarded, yet waiting for review.
    activity.update_columns(status: "under_review")

    error = assert_raises(ActivityReviewService::ReviewError) do
      ActivityReviewService.call(activity: activity, reviewer: @admin,
                                 decision: "rejected", reason: "test")
    end

    assert_match(/already has points/, error.message)
    assert_equal "under_review", activity.reload.status
  end

  # ---- imports ----
  test "an import without a source record ID is refused" do
    start = @base

    result = ActivityCreationService.call(
      user: @user, source: "healthkit",
      attributes: {
        activity_type: "running",
        started_at: start.iso8601,
        ended_at: (start + 30.minutes).iso8601,
        duration_seconds: 1800
      }
    )

    assert_nil result[:activity]
    assert_match(/source record ID/, result[:errors].first)
  end

  test "the same import sent twice is recognised as a duplicate" do
    attributes = {
      source_record_id: "abc-123",
      activity_type: "running",
      started_at: @base.iso8601,
      ended_at: (@base + 30.minutes).iso8601,
      duration_seconds: 1800
    }

    first = ActivityCreationService.call(user: @user, source: "healthkit", attributes: attributes)
    second = ActivityCreationService.call(user: @user, source: "healthkit", attributes: attributes)

    assert first[:activity]
    assert_nil second[:activity]
    assert second[:duplicate]
  end

  test "an import with impossible numbers goes to review" do
    # 50 km in 30 minutes of running is not human
    result = ActivityCreationService.call(
      user: @user, source: "healthkit",
      attributes: {
        source_record_id: "fast-1",
        activity_type: "running",
        started_at: @base.iso8601,
        ended_at: (@base + 30.minutes).iso8601,
        duration_seconds: 1800,
        distance_meters: 50_000
      }
    )

    assert_equal "under_review", result[:activity].status
    assert_match(/Distance/, result[:activity].review_reason)
  end

  # ---- database / model guards ----
  test "the database itself rejects an unknown sport" do
    activity = @user.activities.new(
      activity_type: "chess", source: "manual", status: "eligible",
      started_at: @base, ended_at: @base + 30.minutes, duration_seconds: 1800
    )

    assert_not activity.valid?
    assert_raises(ActiveRecord::StatementInvalid) { activity.save!(validate: false) }
  end

  test "an unrecognised time zone is refused" do
    result = log_manual(time_zone: "Mars/Olympus_Mons")

    assert_nil result[:activity]
    assert_match(/time zone/i, result[:errors].first)
  end

  # ---- scoring rules ----
  test "rules missing a sport cannot be published" do
    version = ScoringRuleVersion.new(
      name: "Broken", version_number: 51, status: "published",
      published_at: Time.current,
      rules: scoring_rule_versions(:one).rules.merge("sport_rates" => { "walking" => 1.0 })
    )

    assert_not version.valid?
    assert_match(
      /must include a positive sport rate for every supported activity type/,
      version.errors.full_messages.join
    )
  end

  test "published rules cannot be edited" do
    version = publish_rules
    version.rules = version.rules.merge("daily_point_cap" => 9999)

    assert_not version.save
    assert_match(/cannot be changed after publishing/, version.errors.full_messages.join)
  end
end

class ActivityEndpointsAuthTest < ActionDispatch::IntegrationTest
  test "the review queue refuses requests with no token" do
    get "/api/v1/activity_reviews"
    assert_response :unauthorized
  end

  test "the import endpoint refuses requests with no token" do
    post "/api/v1/activity_imports", params: {}, as: :json
    assert_response :unauthorized
  end
end
