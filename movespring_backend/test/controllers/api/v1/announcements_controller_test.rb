
require "test_helper"

class Api::V1::AnnouncementsControllerTest < ActionDispatch::IntegrationTest

setup do
  @admin = users(:one)

  @employee = User.create!(
    company: companies(:one),
    name: "Employee One",
    email: "announcement-employee-#{SecureRandom.uuid}@example.com",
    password: "Password123!",
    role: "employee",
    status: "active"
  )

  @second_employee = User.create!(
    company: companies(:one),
    name: "Employee Two",
    email: "announcement-second-employee-#{SecureRandom.uuid}@example.com",
    password: "Password123!",
    role: "employee",
    status: "active"
  )

  @other_company_admin = User.create!(
    company: companies(:two),
    name: "Admin Two",
    email: "announcement-other-admin-#{SecureRandom.uuid}@example.com",
    password: "Password123!",
    role: "company_admin",
    status: "active"
  )

  assert @admin.company_admin?,
         "users(:one) must be a company admin for these tests"

  assert_equal companies(:one), @admin.company
end

  test "announcement listing requires authentication" do
    get api_v1_announcements_path

    assert_response :unauthorized
  end

  test "announcement creation requires authentication" do
    assert_no_difference("Announcement.count") do
      post api_v1_announcements_path,
           params: {
             announcement: {
               title: "Update",
               message: "A company update"
             }
           }
    end

    assert_response :unauthorized
  end

  test "announcement dismissal requires authentication" do
    announcement = create_announcement

    assert_no_difference("AnnouncementDismissal.count") do
      post "/api/v1/announcements/#{announcement.id}/dismiss"
    end

    assert_response :unauthorized
  end

  test "company admin can create and manage an announcement" do
    assert_difference("Announcement.count", 1) do
      post api_v1_announcements_path,
           params: {
             announcement: {
               title: "Update",
               message: "A company update"
             }
           },
           headers: auth_headers(@admin)
    end

    assert_response :created

    announcement_id = response.parsed_body.dig("announcement", "id")
    assert_not_nil announcement_id

    announcement = Announcement.find(announcement_id)

    assert_equal companies(:one), announcement.company
    assert_in_delta Time.current, announcement.starts_at, 2.seconds

    patch "/api/v1/announcements/#{announcement.id}",
          params: {
            announcement: {
              title: "Updated"
            }
          },
          headers: auth_headers(@admin)

    assert_response :ok
    assert_equal "Updated", announcement.reload.title

    assert_difference("Announcement.count", -1) do
      delete "/api/v1/announcements/#{announcement.id}",
             headers: auth_headers(@admin)
    end

    assert_response :ok
    assert_not Announcement.exists?(announcement.id)
  end

  test "company admin cannot assign an announcement to another company" do
    post api_v1_announcements_path,
         params: {
           announcement: {
             title: "Company update",
             message: "A company update",
             company_id: companies(:two).id
           }
         },
         headers: auth_headers(@admin)

    assert_response :created

    announcement_id = response.parsed_body.dig("announcement", "id")
    announcement = Announcement.find(announcement_id)

    assert_equal companies(:one), announcement.company
    assert_not_equal companies(:two), announcement.company
  end

  test "employees cannot create announcements" do
    assert_no_difference("Announcement.count") do
      post api_v1_announcements_path,
           params: {
             announcement: {
               title: "Update",
               message: "A company update"
             }
           },
           headers: auth_headers(@employee)
    end

    assert_response :forbidden
  end

  test "employees cannot update announcements" do
    announcement = create_announcement
    original_title = announcement.title

    patch "/api/v1/announcements/#{announcement.id}",
          params: {
            announcement: {
              title: "Unauthorized change"
            }
          },
          headers: auth_headers(@employee)

    assert_response :forbidden
    assert_equal original_title, announcement.reload.title
  end

  test "employees cannot delete announcements" do
    announcement = create_announcement

    assert_no_difference("Announcement.count") do
      delete "/api/v1/announcements/#{announcement.id}",
             headers: auth_headers(@employee)
    end

    assert_response :forbidden
    assert Announcement.exists?(announcement.id)
  end

  test "employees see only visible announcements" do
    visible = create_announcement(title: "Visible")

    create_announcement(
      title: "Scheduled",
      starts_at: 1.day.from_now
    )

    create_announcement(
      title: "Inactive",
      active: false
    )

    create_announcement(
      title: "Expired",
      starts_at: 2.minutes.ago,
      ends_at: 1.minute.ago
    )

    get api_v1_announcements_path,
        headers: auth_headers(@employee)

    assert_response :ok

    announcements = response.parsed_body.fetch("announcements")
    assert_equal [visible.id], announcements.pluck("id")
  end

  test "employee listing does not include another company's announcements" do
    own_announcement = create_announcement(title: "My company")

    foreign_announcement = companies(:two).announcements.create!(
      title: "Other company",
      message: "This must remain private",
      starts_at: 1.minute.ago,
      active: true
    )

    get api_v1_announcements_path,
        headers: auth_headers(@employee)

    assert_response :ok

    ids = response.parsed_body.fetch("announcements").pluck("id")

    assert_includes ids, own_announcement.id
    assert_not_includes ids, foreign_announcement.id
  end

  test "company admin listing includes inactive, future and expired announcements" do
    active = create_announcement(title: "Active")

    inactive = create_announcement(
      title: "Inactive",
      active: false
    )

    future = create_announcement(
      title: "Future",
      starts_at: 1.day.from_now
    )

    expired = create_announcement(
      title: "Expired",
      starts_at: 2.days.ago,
      ends_at: 1.day.ago
    )

    get api_v1_announcements_path,
        headers: auth_headers(@admin)

    assert_response :ok

    ids = response.parsed_body.fetch("announcements").pluck("id")

    assert_includes ids, active.id
    assert_includes ids, inactive.id
    assert_includes ids, future.id
    assert_includes ids, expired.id
  end

  test "employee listing orders announcements by descending start time and id" do
    earlier = create_announcement(
      title: "Earlier",
      starts_at: 1.hour.ago
    )

    later = create_announcement(
      title: "Later",
      starts_at: 10.minutes.ago
    )

    get api_v1_announcements_path,
        headers: auth_headers(@employee)

    assert_response :ok

    ids = response.parsed_body.fetch("announcements").pluck("id")

    assert_operator ids.index(later.id), :<, ids.index(earlier.id)
  end

  test "employee can dismiss a visible announcement" do
    announcement = create_announcement

    assert_difference("AnnouncementDismissal.count", 1) do
      post "/api/v1/announcements/#{announcement.id}/dismiss",
           headers: auth_headers(@employee)
    end

    assert_response :ok

    assert AnnouncementDismissal.exists?(
      announcement: announcement,
      user: @employee
    )
  end

  test "repeated dismissal does not create duplicate records" do
    announcement = create_announcement

    2.times do
      post "/api/v1/announcements/#{announcement.id}/dismiss",
           headers: auth_headers(@employee)

      assert_response :ok
    end

    assert_equal 1, AnnouncementDismissal.where(
      announcement: announcement,
      user: @employee
    ).count
  end

  test "dismissal is specific to the individual employee" do
    announcement = create_announcement

    post "/api/v1/announcements/#{announcement.id}/dismiss",
         headers: auth_headers(@employee)

    assert_response :ok

    get api_v1_announcements_path,
        headers: auth_headers(@employee)

    assert_response :ok

    employee_ids = response.parsed_body.fetch("announcements").pluck("id")
    assert_not_includes employee_ids, announcement.id

    get api_v1_announcements_path,
        headers: auth_headers(@second_employee)

    assert_response :ok

    second_employee_ids =
      response.parsed_body.fetch("announcements").pluck("id")

    assert_includes second_employee_ids, announcement.id
  end

  test "employees cannot dismiss inactive announcements" do
    announcement = create_announcement(active: false)

    assert_no_difference("AnnouncementDismissal.count") do
      post "/api/v1/announcements/#{announcement.id}/dismiss",
           headers: auth_headers(@employee)
    end

    assert_response :not_found
  end

  test "employees cannot dismiss future announcements" do
    announcement = create_announcement(
      starts_at: 1.day.from_now
    )

    assert_no_difference("AnnouncementDismissal.count") do
      post "/api/v1/announcements/#{announcement.id}/dismiss",
           headers: auth_headers(@employee)
    end

    assert_response :not_found
  end

  test "employees cannot dismiss expired announcements" do
    announcement = create_announcement(
      starts_at: 2.days.ago,
      ends_at: 1.day.ago
    )

    assert_no_difference("AnnouncementDismissal.count") do
      post "/api/v1/announcements/#{announcement.id}/dismiss",
           headers: auth_headers(@employee)
    end

    assert_response :not_found
  end

  test "admin cannot update another company's announcement" do
    announcement = create_announcement

    patch "/api/v1/announcements/#{announcement.id}",
          params: {
            announcement: {
              title: "Other company update"
            }
          },
          headers: auth_headers(@other_company_admin)

    assert_response :not_found
    assert_equal "Company announcement", announcement.reload.title
  end

  test "admin cannot delete another company's announcement" do
    announcement = create_announcement

    assert_no_difference("Announcement.count") do
      delete "/api/v1/announcements/#{announcement.id}",
             headers: auth_headers(@other_company_admin)
    end

    assert_response :not_found
    assert Announcement.exists?(announcement.id)
  end

  test "user cannot dismiss another company's announcement" do
    announcement = create_announcement

    assert_no_difference("AnnouncementDismissal.count") do
      post "/api/v1/announcements/#{announcement.id}/dismiss",
           headers: auth_headers(@other_company_admin)
    end

    assert_response :not_found
  end

  test "invalid announcement dates are rejected" do
    assert_no_difference("Announcement.count") do
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
    end

    assert_response :unprocessable_entity
  end

  test "equal start and end times are rejected" do
    timestamp = 1.day.from_now

    assert_no_difference("Announcement.count") do
      post api_v1_announcements_path,
           params: {
             announcement: {
               title: "Equal dates",
               message: "Start and end cannot be equal",
               starts_at: timestamp,
               ends_at: timestamp
             }
           },
           headers: auth_headers(@admin)
    end

    assert_response :unprocessable_entity
  end

  test "empty title is rejected" do
    assert_no_difference("Announcement.count") do
      post api_v1_announcements_path,
           params: {
             announcement: {
               title: "",
               message: "A company update"
             }
           },
           headers: auth_headers(@admin)
    end

    assert_response :unprocessable_entity
  end

  test "title longer than 150 characters is rejected" do
    assert_no_difference("Announcement.count") do
      post api_v1_announcements_path,
           params: {
             announcement: {
               title: "x" * 151,
               message: "A company update"
             }
           },
           headers: auth_headers(@admin)
    end

    assert_response :unprocessable_entity
  end

  test "message longer than 5000 characters is rejected" do
    assert_no_difference("Announcement.count") do
      post api_v1_announcements_path,
           params: {
             announcement: {
               title: "Company update",
               message: "x" * 5001
             }
           },
           headers: auth_headers(@admin)
    end

    assert_response :unprocessable_entity
  end

  test "missing starts_at defaults to the current time" do
    post api_v1_announcements_path,
         params: {
           announcement: {
             title: "Default start",
             message: "The controller should set the start time"
           }
         },
         headers: auth_headers(@admin)

    assert_response :created

    announcement_id = response.parsed_body.dig("announcement", "id")
    announcement = Announcement.find(announcement_id)

    assert_in_delta Time.current, announcement.starts_at, 2.seconds
  end

  test "updating a nonexistent announcement returns not found" do
    patch "/api/v1/announcements/999999999",
          params: {
            announcement: {
              title: "Updated"
            }
          },
          headers: auth_headers(@admin)

    assert_response :not_found
  end

  test "deleting a nonexistent announcement returns not found" do
    delete "/api/v1/announcements/999999999",
           headers: auth_headers(@admin)

    assert_response :not_found
  end

  test "dismissing a nonexistent announcement returns not found" do
    post "/api/v1/announcements/999999999/dismiss",
         headers: auth_headers(@employee)

    assert_response :not_found
  end

  private

  def auth_headers(user)
    {
      "Authorization" => "Bearer #{TokenService.issue(user)}"
    }
  end

  def create_announcement(attributes = {})
    companies(:one).announcements.create!(
      {
        title: "Company announcement",
        message: "Details for employees",
        starts_at: 1.minute.ago,
        active: true
      }.merge(attributes)
    )
  end
end
