
require "test_helper"
require "securerandom"

class NotificationsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create_company("Company A")

    @employee = create_user(
      @company,
      role: "employee",
      name: "Employee One"
    )

    @other_employee = create_user(
      @company,
      role: "employee",
      name: "Employee Two"
    )
  end

  test "unauthenticated users cannot access notifications" do
    get "/api/v1/notifications"

    assert_response :unauthorized
  end

  test "employee can view their own notifications" do
    notification = create_notification(@employee)

    get "/api/v1/notifications",
        headers: auth_headers(@employee)

    assert_response :ok

    notifications = response.parsed_body["notifications"]

    assert_equal 1, notifications.length
    assert_equal notification.id, notifications.first["id"]
    assert_equal "personal_record", notifications.first["notification_type"]
    assert_equal "New personal record", notifications.first["title"]
  end

  test "employees cannot see another employee's notifications" do
    create_notification(@employee)
    create_notification(@other_employee, title: "Private notification")

    get "/api/v1/notifications",
        headers: auth_headers(@employee)

    assert_response :ok

    notifications = response.parsed_body["notifications"]

    assert_equal 1, notifications.length
    assert_equal "New personal record", notifications.first["title"]
  end

  test "employee can filter notifications by unread status" do
    create_notification(@employee)

    read_notification = create_notification(
      @employee,
      title: "Already read notification"
    )
    read_notification.mark_as_read!

    get "/api/v1/notifications",
        params: { unread: true },
        headers: auth_headers(@employee)

    assert_response :ok

    notifications = response.parsed_body["notifications"]

    assert_equal 1, notifications.length
    assert_equal "New personal record", notifications.first["title"]

    get "/api/v1/notifications",
        params: { unread: false },
        headers: auth_headers(@employee)

    assert_response :ok

    notifications = response.parsed_body["notifications"]

    assert_equal 1, notifications.length
    assert_equal "Already read notification", notifications.first["title"]
  end

  test "employee can retrieve their unread notification count" do
    create_notification(@employee)

    read_notification = create_notification(
      @employee,
      title: "Already read notification"
    )
    read_notification.mark_as_read!

    get "/api/v1/notifications/unread_count",
        headers: auth_headers(@employee)

    assert_response :ok

    assert_equal 1, response.parsed_body["unread_count"]
  end

  test "employee can mark their own notification as read" do
    notification = create_notification(@employee)

    patch "/api/v1/notifications/#{notification.id}/read",
          headers: auth_headers(@employee)

    assert_response :ok

    assert notification.reload.read_at.present?
  end

  test "employee cannot mark another employee's notification as read" do
    notification = create_notification(@other_employee)

    patch "/api/v1/notifications/#{notification.id}/read",
          headers: auth_headers(@employee)

    assert_response :not_found

    assert_nil notification.reload.read_at
  end

  test "employee can mark all their notifications as read" do
    first_notification = create_notification(@employee)
    second_notification = create_notification(
      @employee,
      title: "Another notification"
    )
    other_notification = create_notification(@other_employee)

    patch "/api/v1/notifications/read_all",
          headers: auth_headers(@employee)

    assert_response :ok

    assert first_notification.reload.read_at.present?
    assert second_notification.reload.read_at.present?

    assert_nil other_notification.reload.read_at
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
      status: "active",
      email_verified_at: Time.current
    )
  end

  def create_notification(user, **attributes)
    user.notifications.create!(
      {
        notification_type: "personal_record",
        title: "New personal record",
        message: "You achieved a new running record!",
        data: { record_type: "longest_run" }
      }.merge(attributes)
    )
  end

  def auth_headers(user)
    {
      "Authorization" => "Bearer #{TokenService.issue(user)}"
    }
  end
end
