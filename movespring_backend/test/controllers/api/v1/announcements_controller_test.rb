require "test_helper"

class Api::V1::AnnouncementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    @employee = User.create!(
      company: companies(:one),
      name: "Employee One",
      email: "employee-one@example.com",
      password: "Password123!",
      role: "employee",
      status: "active"
    )
    @other_company_admin = User.create!(
      company: companies(:two),
      name: "Admin Two",
      email: "admin-two@example.com",
      password: "Password123!",
      role: "company_admin",
      status: "active"
    )
  end

  test "company admin can create and manage an announcement" do
    post api_v1_announcements_path,
         params: { announcement: { title: "Update", message: "A company update" } },
         headers: auth_headers(@admin)

    assert_response :created
    announcement_id = response.parsed_body.dig("announcement", "id")
    announcement = Announcement.find(announcement_id)
    assert_equal companies(:one), announcement.company
    assert_in_delta Time.current, announcement.starts_at, 2.seconds

    patch "/api/v1/announcements/#{announcement.id}",
          params: { announcement: { title: "Updated" } },
          headers: auth_headers(@admin)

    assert_response :ok
    assert_equal "Updated", announcement.reload.title

    delete "/api/v1/announcements/#{announcement.id}",
           headers: auth_headers(@admin)

    assert_response :ok
    assert_not Announcement.exists?(announcement.id)
  end

  test "employees see only visible announcements and dismissals persist per user" do
    visible = create_announcement(title: "Visible")
    create_announcement(title: "Scheduled", starts_at: 1.day.from_now)
    create_announcement(title: "Inactive", active: false)
    create_announcement(title: "Expired", starts_at: 2.minutes.ago, ends_at: 1.minute.ago)

    get api_v1_announcements_path, headers: auth_headers(@employee)

    assert_response :ok
    assert_equal [ visible.id ], response.parsed_body.fetch("announcements").pluck("id")

    post "/api/v1/announcements/#{visible.id}/dismiss",
         headers: auth_headers(@employee)

    assert_response :ok
    assert AnnouncementDismissal.exists?(
      announcement: visible,
      user: @employee
    )

    get api_v1_announcements_path, headers: auth_headers(@employee)

    assert_response :ok
    assert_empty response.parsed_body.fetch("announcements")
  end

  test "employees cannot manage announcements" do
    post api_v1_announcements_path,
         params: { announcement: { title: "Update", message: "A company update" } },
         headers: auth_headers(@employee)

    assert_response :forbidden
  end

  test "announcements are scoped to the current company" do
    announcement = create_announcement

    patch "/api/v1/announcements/#{announcement.id}",
          params: { announcement: { title: "Other company update" } },
          headers: auth_headers(@other_company_admin)

    assert_response :not_found
    assert_equal "Company announcement", announcement.reload.title

    post "/api/v1/announcements/#{announcement.id}/dismiss",
         headers: auth_headers(@other_company_admin)

    assert_response :not_found
  end

  test "invalid announcement dates are rejected" do
    post api_v1_announcements_path,
         params: {
           announcement: {
             title: "Invalid dates",
             message: "End must be after start",
             starts_at: 2.days.from_now,
             ends_at: 1.day.from_now
           }
         },
         headers: auth_headers(@admin)

    assert_response :unprocessable_entity
    assert_empty Announcement.where(title: "Invalid dates")
  end

  private

  def auth_headers(user)
    { "Authorization" => "Bearer #{TokenService.issue(user)}" }
  end

  def create_announcement(attributes = {})
    companies(:one).announcements.create!(
      {
        title: "Company announcement",
        message: "Details for employees",
        starts_at: 1.minute.ago
      }.merge(attributes)
    )
  end
end
