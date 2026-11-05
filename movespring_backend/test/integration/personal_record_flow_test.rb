
require "test_helper"
require "securerandom"

class PersonalRecordFlowTest < ActionDispatch::IntegrationTest
  setup do
    @company = Company.create!(
      name: "Personal Records Company",
      slug: "personal-records-#{SecureRandom.hex(4)}",
      status: "active",
      time_zone: "Africa/Johannesburg"
    )

    @employee = create_user(
      @company,
      role: "employee",
      name: "Employee One"
    )

    @admin = create_user(
      @company,
      role: "company_admin",
      name: "Company Admin"
    )
  end

  test "manual activity creates a personal record notification that the employee can read" do
    started_at = 2.hours.ago
    ended_at = started_at + 30.minutes

    # 1. Employee submits a 5 km running activity.
    post "/api/v1/activities",
         params: {
           activity: {
             activity_type: "running",
             started_at: started_at.iso8601,
             ended_at: ended_at.iso8601,
             distance_meters: 5000,
             steps: 6000,
             active_calories: 300,
             reported_intensity: 5,
             time_zone: "Africa/Johannesburg"
           }
         },
         headers: auth_headers(@employee),
         as: :json

    assert_response :created

    activity_id = response.parsed_body.dig("activity", "id")
    activity = Activity.find(activity_id)

    # 2. The activity must be eligible.
    assert_equal "eligible", activity.status

    # 3. The activity must have received points.
    award = ActivityPointAward.find_by(activity: activity)

    assert_not_nil award
    assert_operator award.points, :>, 0

    # 4. A longest_run personal record event must exist.
    event = PersonalRecordEvent.find_by(
      user: @employee,
      activity: activity,
      record_type: "longest_run"
    )

    assert_not_nil event
    assert_equal 5000.0, event.new_value.to_f
    assert_nil event.read_at

    # 5. Employee retrieves the event through the API.
    get "/api/v1/personal_record_events",
        headers: auth_headers(@employee)

    assert_response :ok

    events = response.parsed_body.fetch("personal_record_events")

    returned_event = events.find { |item| item["id"] == event.id }

    assert_not_nil returned_event
    assert_equal "longest_run", returned_event["record_type"]
    assert_equal false, returned_event["read"]

    # 6. Employee marks the event as read.
    patch "/api/v1/personal_record_events/#{event.id}/read",
          headers: auth_headers(@employee)

    assert_response :ok
    assert event.reload.read_at.present?
  end

  test "administrator approval creates a personal record notification" do
    started_at = 2.hours.ago

    # 1. Create a pending imported activity awaiting administrator review.
    activity = @employee.activities.create!(
      activity_type: "running",
      source: "health_connect",
      status: "pending",
      started_at: started_at,
      ended_at: started_at + 30.minutes,
      duration_seconds: 1800,
      distance_meters: 5000,
      steps: 6000,
      active_calories: 300,
      average_heart_rate: 150,
      intensity_source: "heart_rate",
      time_zone: "Africa/Johannesburg"
    )

    # 2. The company administrator approves the activity.
    post "/api/v1/activities/#{activity.id}/review",
         params: { decision: "approved" },
         headers: auth_headers(@admin),
         as: :json

    assert_response :ok

    # 3. Confirm the activity became eligible and received points.
    assert_equal "eligible", activity.reload.status

    award = ActivityPointAward.find_by(activity: activity)

    assert_not_nil award
    assert_operator award.points, :>, 0

    # 4. Confirm the personal record event was created.
    event = PersonalRecordEvent.find_by(
      user: @employee,
      activity: activity,
      record_type: "longest_run"
    )

    assert_not_nil event
    assert_equal 5000.0, event.new_value.to_f

    # 5. Confirm the employee can retrieve the notification.
    get "/api/v1/personal_record_events",
        headers: auth_headers(@employee)

    assert_response :ok

    events = response.parsed_body.fetch("personal_record_events")

    assert events.any? { |item| item["id"] == event.id }
  end

  private

  def create_user(company, role:, name:)
    User.create!(
      company: company,
      name: name,
      email: "user-#{SecureRandom.hex(8)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: role,
      status: "active",
      email_verified_at: Time.current
    )
  end

  def auth_headers(user)
    {
      "Authorization" => "Bearer #{TokenService.issue(user)}"
    }
  end
end
