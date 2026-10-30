
require "test_helper"
require "securerandom"

class PersonalRecordEventsTest < ActionDispatch::IntegrationTest
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

  test "unauthenticated users cannot access personal record events" do
    get "/api/v1/personal_record_events"

    assert_response :unauthorized
  end

  test "employee can view their own personal record events" do
    event = create_event(@employee, new_value: 5000)

    get "/api/v1/personal_record_events",
        headers: auth_headers(@employee)

    assert_response :ok

    events = response.parsed_body["personal_record_events"]

    assert_equal 1, events.length
    assert_equal event.id, events.first["id"]
    assert_equal "longest_run", events.first["record_type"]
    assert_equal 5000.0, events.first["new_value"]
  end

  test "employees cannot see another employee's personal record events" do
    create_event(@employee, new_value: 5000)
    create_event(@other_employee, new_value: 8000)

    get "/api/v1/personal_record_events",
        headers: auth_headers(@employee)

    assert_response :ok

    events = response.parsed_body["personal_record_events"]

    assert_equal 1, events.length
    assert_equal 5000.0, events.first["new_value"]
  end

  test "employee can filter personal record events by unread status" do
    create_event(@employee, new_value: 5000)
    read_event = create_event(@employee, new_value: 6000)
    read_event.update!(read_at: Time.current)

    get "/api/v1/personal_record_events",
        params: { unread: true },
        headers: auth_headers(@employee)

    assert_response :ok

    events = response.parsed_body["personal_record_events"]

    assert_equal 1, events.length
    assert_equal 5000.0, events.first["new_value"]

    get "/api/v1/personal_record_events",
        params: { unread: false },
        headers: auth_headers(@employee)

    assert_response :ok

    events = response.parsed_body["personal_record_events"]

    assert_equal 1, events.length
    assert_equal 6000.0, events.first["new_value"]
  end

  test "employee can retrieve their unread personal record event count" do
    create_event(@employee, new_value: 5000)
    read_event = create_event(@employee, new_value: 6000)
    read_event.update!(read_at: Time.current)

    get "/api/v1/personal_record_events/unread_count",
        headers: auth_headers(@employee)

    assert_response :ok

    assert_equal 1, response.parsed_body["unread_count"]
  end

  test "employee can mark their own personal record event as read" do
    event = create_event(@employee, new_value: 5000)

    patch "/api/v1/personal_record_events/#{event.id}/read",
          headers: auth_headers(@employee)

    assert_response :ok

    assert event.reload.read_at.present?
  end

  test "employee cannot mark another employee's event as read" do
    event = create_event(@other_employee, new_value: 5000)

    patch "/api/v1/personal_record_events/#{event.id}/read",
          headers: auth_headers(@employee)

    assert_response :not_found

    assert_nil event.reload.read_at
  end

  test "employee can mark all their personal record events as read" do
    first_event = create_event(@employee, new_value: 5000)
    second_event = create_event(@employee, new_value: 6000)
    other_event = create_event(@other_employee, new_value: 7000)

    patch "/api/v1/personal_record_events/read_all",
          headers: auth_headers(@employee)

    assert_response :ok

    assert first_event.reload.read_at.present?
    assert second_event.reload.read_at.present?

    assert_nil other_event.reload.read_at
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

  def create_event(user, **attributes)
    user.personal_record_events.create!(
      {
        record_type: "longest_run",
        previous_value: nil,
        new_value: 5000,
        achieved_at: Time.current
      }.merge(attributes)
    )
  end

  def auth_headers(user)
    {
      "Authorization" => "Bearer #{TokenService.issue(user)}"
    }
  end
end
