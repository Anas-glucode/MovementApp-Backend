require "test_helper"
require "securerandom"

class ActivityReviewsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create_company("Company A")

    @admin = create_user(
      @company,
      role: "company_admin",
      name: "Company Admin"
    )

    @employee = create_user(
      @company,
      role: "employee",
      name: "Employee One"
    )

    @other_company = create_company("Company B")

    @other_employee = create_user(
      @other_company,
      role: "employee",
      name: "Employee Two"
    )

    @activity = create_reviewable_activity(@employee)
  end

  test "company administrator can approve an activity and award points" do
    post "/api/v1/activities/#{@activity.id}/review",
         params: { decision: "approved" },
         headers: auth_headers(@admin),
         as: :json

    assert_response :ok

    body = response.parsed_body

    assert_equal "approved", body.dig("review", "decision")
    assert_equal "eligible", body.dig("activity", "status")
    assert_equal 30, body["points_awarded"]

    @activity.reload
    assert_equal "eligible", @activity.status
    assert ActivityReview.exists?(
      activity: @activity,
      reviewer: @admin,
      decision: "approved"
    )
    assert_equal 1, ActivityPointAward.where(activity: @activity).count
  end

  test "company administrator can reject an activity with a reason" do
    post "/api/v1/activities/#{@activity.id}/review",
         params: {
           decision: "rejected",
           reason: "The submitted activity could not be verified."
         },
         headers: auth_headers(@admin),
         as: :json

    assert_response :ok

    body = response.parsed_body

    assert_equal "rejected", body.dig("review", "decision")
    assert_equal "The submitted activity could not be verified.",
                 body.dig("review", "reason")
    assert_equal "rejected", body.dig("activity", "status")
    assert_nil body["points_awarded"]

    assert_equal "rejected", @activity.reload.status
    assert_equal 0, ActivityPointAward.where(activity: @activity).count
  end

  test "employees cannot review activities" do
    post "/api/v1/activities/#{@activity.id}/review",
         params: { decision: "approved" },
         headers: auth_headers(@employee),
         as: :json

    assert_response :forbidden
    assert_equal "pending", @activity.reload.status
    assert_not ActivityReview.exists?(activity: @activity)
  end

  test "administrators cannot review activities from another company" do
    other_activity = create_reviewable_activity(@other_employee)

    post "/api/v1/activities/#{other_activity.id}/review",
         params: { decision: "approved" },
         headers: auth_headers(@admin),
         as: :json

    assert_response :not_found
    assert_equal "pending", other_activity.reload.status
    assert_not ActivityReview.exists?(activity: other_activity)
  end

  test "an activity cannot be reviewed twice" do
    post "/api/v1/activities/#{@activity.id}/review",
         params: {
           decision: "rejected",
           reason: "Unable to verify."
         },
         headers: auth_headers(@admin),
         as: :json

    assert_response :ok

    post "/api/v1/activities/#{@activity.id}/review",
         params: { decision: "approved" },
         headers: auth_headers(@admin),
         as: :json

    assert_response :unprocessable_entity
    assert_equal "rejected", @activity.reload.status
    assert_equal 1, ActivityReview.where(activity: @activity).count
    assert_equal 0, ActivityPointAward.where(activity: @activity).count
  end

  test "rejection requires a reason" do
    post "/api/v1/activities/#{@activity.id}/review",
         params: { decision: "rejected" },
         headers: auth_headers(@admin),
         as: :json

    assert_response :unprocessable_entity
    assert_equal "pending", @activity.reload.status
    assert_not ActivityReview.exists?(activity: @activity)
  end

  test "invalid review decisions are rejected" do
    post "/api/v1/activities/#{@activity.id}/review",
         params: { decision: "maybe" },
         headers: auth_headers(@admin),
         as: :json

    assert_response :unprocessable_entity
    assert_equal "pending", @activity.reload.status
    assert_not ActivityReview.exists?(activity: @activity)
  end

  test "approval fails safely when no published scoring rules exist" do
    ScoringRuleVersion.where(status: "published")
                      .update_all(status: "retired")

    post "/api/v1/activities/#{@activity.id}/review",
         params: { decision: "approved" },
         headers: auth_headers(@admin),
         as: :json

    assert_response :unprocessable_entity
    assert_equal "pending", @activity.reload.status
    assert_not ActivityReview.exists?(activity: @activity)
    assert_equal 0, ActivityPointAward.where(activity: @activity).count
  end


  test "company administrator can view only reviewable activities in their company without heart rate data" do
    flagged_activity = create_reviewable_activity(@employee)
    flagged_activity.update!(
      status: "under_review",
      review_reason: "Manual activity requires review",
      average_heart_rate: 165
    )

    eligible_activity = create_reviewable_activity(@employee)
    eligible_activity.update!(status: "eligible")

    rejected_activity = create_reviewable_activity(@employee)
    rejected_activity.update!(status: "rejected")

    other_company_activity = create_reviewable_activity(@other_employee)

    get "/api/v1/activity_reviews",
        headers: auth_headers(@admin),
        as: :json

    assert_response :ok

    body = response.parsed_body
    activities = body.fetch("activities")
    activity_ids = activities.map { |activity| activity.fetch("id") }

    assert_includes activity_ids, @activity.id
    assert_includes activity_ids, flagged_activity.id

    assert_not_includes activity_ids, eligible_activity.id
    assert_not_includes activity_ids, rejected_activity.id
    assert_not_includes activity_ids, other_company_activity.id

    flagged_json = activities.find do |activity|
      activity["id"] == flagged_activity.id
    end

    assert_equal "Employee One", flagged_json.dig("employee", "name")
    assert_equal "under_review", flagged_json["status"]
    assert_equal "Manual activity requires review",
                 flagged_json["review_reason"]

    assert_not_includes response.body, "average_heart_rate"
    assert_not_includes response.body, "165"
  end

  test "employees cannot access the activity review queue" do
    get "/api/v1/activity_reviews",
        headers: auth_headers(@employee),
        as: :json

    assert_response :forbidden
    assert_equal(
      "Only company administrators can review activities",
      response.parsed_body["error"]
    )
  end


  test "company administrator can view reviewable activity details without heart rate data" do
    @activity.update!(average_heart_rate: 150)

    get "/api/v1/activity_reviews/#{@activity.id}",
        headers: auth_headers(@admin),
        as: :json

    assert_response :ok

    activity_json = response.parsed_body.fetch("activity")

    assert_equal @activity.id, activity_json["id"]
    assert_equal "Employee One", activity_json.dig("employee", "name")
    assert_equal "walking", activity_json["activity_type"]
    assert_equal "pending", activity_json["status"]
    assert_not_includes response.body, "average_heart_rate"
    assert_not_includes response.body, "150"
  end

  test "administrator cannot view another company's activity details" do
    other_activity = create_reviewable_activity(@other_employee)

    get "/api/v1/activity_reviews/#{other_activity.id}",
        headers: auth_headers(@admin),
        as: :json

    assert_response :not_found
  end

  test "employees cannot view activity review details" do
    get "/api/v1/activity_reviews/#{@activity.id}",
        headers: auth_headers(@employee),
        as: :json

    assert_response :forbidden
  end

  private

  def create_company(name)
    Company.create!(
      name: name,
      slug: "#{name.parameterize}-#{SecureRandom.hex(4)}",
      status: "active"
    )
  end

  def create_user(company, role:, name:)
    User.create!(
      company: company,
      name: name,
      email: "user-#{SecureRandom.hex(8)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: role,
      status: "active"
    )
  end

  def create_reviewable_activity(user)
    started_at = 1.hour.ago

    Activity.create!(
      user: user,
      activity_type: "walking",
      source: "health_connect",
      started_at: started_at,
      ended_at: started_at + 30.minutes,
      duration_seconds: 1800,
      status: "pending",
      time_zone: "Africa/Johannesburg"
    )
  end

  def auth_headers(user)
    {
      "Authorization" => "Bearer #{TokenService.issue(user)}"
    }
  end
end
