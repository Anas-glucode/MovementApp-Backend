
require "test_helper"
require "securerandom"

class AnnouncementsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create_company("Company A")
    @admin = create_user(@company, "company_admin")
    @employee = create_user(@company, "employee")
    @second_employee = create_user(@company, "employee")
    @inactive_employee = create_user(
      @company,
      "employee",
      status: "inactive"
    )

    @other_company = create_company("Company B")
    @other_admin = create_user(@other_company, "company_admin")
    @other_employee = create_user(@other_company, "employee")
  end

  test "unauthenticated users cannot access announcements" do
    get "/api/v1/announcements"

    assert_response :unauthorized
  end

  test "company administrator can create a draft announcement" do
    assert_difference "Announcement.count", 1 do
      post "/api/v1/announcements",
           params: {
             announcement: {
               title: "Important Update",
               body: "We have an important company update."
             }
           },
           headers: auth_headers(@admin),
           as: :json
    end

    assert_response :created

    announcement = Announcement.find(
      response.parsed_body.dig("announcement", "id")
    )

    assert_equal @company.id, announcement.company_id
    assert_equal @admin.id, announcement.created_by_id
    assert_equal "draft", announcement.status
  end

  test "client cannot choose announcement company creator or status" do
    post "/api/v1/announcements",
         params: {
           announcement: {
             title: "Protected Announcement",
             body: "Testing protected fields.",
             company_id: @other_company.id,
             created_by_id: @other_admin.id,
             status: "published",
             published_at: 1.day.ago.iso8601
           }
         },
         headers: auth_headers(@admin),
         as: :json

    assert_response :created

    announcement = Announcement.find(
      response.parsed_body.dig("announcement", "id")
    )

    assert_equal @company.id, announcement.company_id
    assert_equal @admin.id, announcement.created_by_id
    assert_equal "draft", announcement.status
    assert_nil announcement.published_at
  end

  test "employee cannot create an announcement" do
    assert_no_difference "Announcement.count" do
      post "/api/v1/announcements",
           params: {
             announcement: {
               title: "Unauthorised",
               body: "Employees cannot create announcements."
             }
           },
           headers: auth_headers(@employee),
           as: :json
    end

    assert_response :forbidden
  end

  test "administrator lists all announcements in their own company" do
    draft = create_announcement(@company, @admin)
    published = create_announcement(
      @company,
      @admin,
      status: "published"
    )
    archived = create_announcement(
      @company,
      @admin,
      status: "archived"
    )
    create_announcement(@other_company, @other_admin, status: "published")

    get "/api/v1/announcements",
        headers: auth_headers(@admin),
        as: :json

    assert_response :ok

    ids = response.parsed_body.fetch("announcements").map do |item|
      item["id"]
    end

    assert_includes ids, draft.id
    assert_includes ids, published.id
    assert_includes ids, archived.id
    assert_equal 3, ids.length
  end

  test "employee only sees published announcements that are available" do
    published = create_announcement(
      @company,
      @admin,
      status: "published"
    )

    create_announcement(@company, @admin)

    create_announcement(
      @company,
      @admin,
      status: "archived"
    )

    create_announcement(
      @company,
      @admin,
      status: "published",
      published_at: 1.day.from_now
    )

    create_announcement(
      @other_company,
      @other_admin,
      status: "published"
    )

    get "/api/v1/announcements",
        headers: auth_headers(@employee),
        as: :json

    assert_response :ok

    announcements = response.parsed_body.fetch("announcements")
    ids = announcements.map { |item| item["id"] }

    assert_equal [published.id], ids
  end

  test "employee cannot view a draft announcement" do
    announcement = create_announcement(@company, @admin)

    get "/api/v1/announcements/#{announcement.id}",
        headers: auth_headers(@employee),
        as: :json

    assert_response :not_found
  end

  test "employee cannot view another company's announcement" do
    announcement = create_announcement(
      @other_company,
      @other_admin,
      status: "published"
    )

    get "/api/v1/announcements/#{announcement.id}",
        headers: auth_headers(@employee),
        as: :json

    assert_response :not_found
  end

  test "employee can view an archived announcement if they received its notification" do
  announcement = create_announcement(
    @company,
    @admin,
    status: "archived"
  )

  @employee.notifications.create!(
    notification_type: "announcement",
    title: announcement.title,
    message: announcement.body,
    data: { announcement_id: announcement.id },
    notifiable: announcement
  )

  get "/api/v1/announcements/#{announcement.id}",
      headers: auth_headers(@employee),
      as: :json

  assert_response :ok

  assert_equal announcement.id,
               response.parsed_body.dig("announcement", "id")
end

test "employee cannot view an archived announcement without its notification" do
  announcement = create_announcement(
    @company,
    @admin,
    status: "archived"
  )

  get "/api/v1/announcements/#{announcement.id}",
      headers: auth_headers(@employee),
      as: :json

  assert_response :not_found
end

  test "administrator can edit a draft announcement" do
    announcement = create_announcement(@company, @admin)

    patch "/api/v1/announcements/#{announcement.id}",
          params: {
            announcement: {
              title: "Updated Title",
              body: "Updated announcement body."
            }
          },
          headers: auth_headers(@admin),
          as: :json

    assert_response :ok

    assert_equal "Updated Title", announcement.reload.title
    assert_equal "Updated announcement body.", announcement.body
  end

  test "published announcement cannot be edited" do
    announcement = create_announcement(
      @company,
      @admin,
      status: "published"
    )

    patch "/api/v1/announcements/#{announcement.id}",
          params: {
            announcement: { title: "Attempted Change" }
          },
          headers: auth_headers(@admin),
          as: :json

    assert_response :unprocessable_entity
    assert_equal "Test Announcement", announcement.reload.title
  end

  test "employee cannot publish an announcement" do
    announcement = create_announcement(@company, @admin)

    patch "/api/v1/announcements/#{announcement.id}/publish",
          headers: auth_headers(@employee),
          as: :json

    assert_response :forbidden
    assert_equal "draft", announcement.reload.status
  end

  test "publishing creates notifications for active employees in the same company" do
    announcement = create_announcement(@company, @admin)

    patch "/api/v1/announcements/#{announcement.id}/publish",
          headers: auth_headers(@admin),
          as: :json

    assert_response :ok

    assert_equal "published", announcement.reload.status
    assert_not_nil announcement.published_at

    notification = @employee.notifications.find_by!(
      notifiable: announcement
    )

    assert_equal "announcement", notification.notification_type
    assert_equal announcement.title, notification.title
    assert_equal announcement.body, notification.message

    assert @second_employee.notifications.exists?(
      notifiable: announcement
    )

    assert_equal 0, @inactive_employee.notifications.where(
      notifiable: announcement
    ).count

    assert_equal 0, @other_employee.notifications.where(
      notifiable: announcement
    ).count
  end

  test "administrator cannot publish another company's announcement" do
    announcement = create_announcement(
      @other_company,
      @other_admin
    )

    patch "/api/v1/announcements/#{announcement.id}/publish",
          headers: auth_headers(@admin),
          as: :json

    assert_response :not_found
    assert_equal "draft", announcement.reload.status
  end

  test "administrator can archive a published announcement" do
    announcement = create_announcement(
      @company,
      @admin,
      status: "published"
    )

    patch "/api/v1/announcements/#{announcement.id}/archive",
          headers: auth_headers(@admin),
          as: :json

    assert_response :ok
    assert_equal "archived", announcement.reload.status
  end

  test "administrator cannot archive a draft announcement" do
    announcement = create_announcement(@company, @admin)

    patch "/api/v1/announcements/#{announcement.id}/archive",
          headers: auth_headers(@admin),
          as: :json

    assert_response :unprocessable_entity
    assert_equal "draft", announcement.reload.status
  end

  test "administrator can delete a draft announcement" do
    announcement = create_announcement(@company, @admin)

    assert_difference "Announcement.count", -1 do
      delete "/api/v1/announcements/#{announcement.id}",
             headers: auth_headers(@admin),
             as: :json
    end

    assert_response :ok
  end

  test "published announcement cannot be deleted" do
    announcement = create_announcement(
      @company,
      @admin,
      status: "published"
    )

    assert_no_difference "Announcement.count" do
      delete "/api/v1/announcements/#{announcement.id}",
             headers: auth_headers(@admin),
             as: :json
    end

    assert_response :unprocessable_entity
  end

  test "employee can mark a published announcement as read" do
    announcement = create_announcement(
      @company,
      @admin,
      status: "published"
    )

    assert_difference "AnnouncementRead.count", 1 do
      patch "/api/v1/announcements/#{announcement.id}/read",
            headers: auth_headers(@employee),
            as: :json
    end

    assert_response :ok

    read_record = AnnouncementRead.find_by!(
      announcement: announcement,
      user: @employee
    )

    assert_not_nil read_record.read_at
  end

  test "marking the same announcement as read twice does not create duplicates" do
    announcement = create_announcement(
      @company,
      @admin,
      status: "published"
    )

    patch "/api/v1/announcements/#{announcement.id}/read",
          headers: auth_headers(@employee),
          as: :json

    assert_response :ok

    original_read_at = AnnouncementRead.find_by!(
      announcement: announcement,
      user: @employee
    ).read_at

    assert_no_difference "AnnouncementRead.count" do
      patch "/api/v1/announcements/#{announcement.id}/read",
            headers: auth_headers(@employee),
            as: :json
    end

    assert_response :ok

    assert_equal original_read_at,
                 AnnouncementRead.find_by!(
                   announcement: announcement,
                   user: @employee
                 ).read_at
  end

  test "employee cannot mark another company's announcement as read" do
    announcement = create_announcement(
      @other_company,
      @other_admin,
      status: "published"
    )

    assert_no_difference "AnnouncementRead.count" do
      patch "/api/v1/announcements/#{announcement.id}/read",
            headers: auth_headers(@employee),
            as: :json
    end

    assert_response :not_found
  end

  test "employee cannot mark a draft announcement as read" do
    announcement = create_announcement(@company, @admin)

    patch "/api/v1/announcements/#{announcement.id}/read",
          headers: auth_headers(@employee),
          as: :json

    assert_response :not_found
    assert_equal 0, AnnouncementRead.where(
      announcement: announcement,
      user: @employee
    ).count
  end

  test "employee can mark an archived announcement as read if they received its notification" do
  announcement = create_announcement(
    @company,
    @admin,
    status: "archived"
  )

  @employee.notifications.create!(
    notification_type: "announcement",
    title: announcement.title,
    message: announcement.body,
    data: { announcement_id: announcement.id },
    notifiable: announcement
  )

  assert_difference "AnnouncementRead.count", 1 do
    patch "/api/v1/announcements/#{announcement.id}/read",
          headers: auth_headers(@employee),
          as: :json
  end

  assert_response :ok

  assert AnnouncementRead.exists?(
    announcement: announcement,
    user: @employee
  )
end

  test "administrator cannot use the employee mark-as-read endpoint" do
    announcement = create_announcement(
      @company,
      @admin,
      status: "published"
    )

    patch "/api/v1/announcements/#{announcement.id}/read",
          headers: auth_headers(@admin),
          as: :json

    assert_response :forbidden
  end

  test "employee sees their own read status in announcement details" do
    announcement = create_announcement(
      @company,
      @admin,
      status: "published"
    )

    patch "/api/v1/announcements/#{announcement.id}/read",
          headers: auth_headers(@employee),
          as: :json

    get "/api/v1/announcements/#{announcement.id}",
        headers: auth_headers(@employee),
        as: :json

    assert_response :ok

    read_at = response.parsed_body.dig(
      "announcement",
      "read_at"
    )

    assert_not_nil read_at
  end

  private

  def create_company(name)
    Company.create!(
      name: name,
      slug: "#{name.parameterize}-#{SecureRandom.hex(4)}",
      status: "active"
    )
  end

  def create_user(company, role, status: "active")
    User.create!(
      company: company,
      name: "Test #{role.humanize}",
      email: "#{role}-#{SecureRandom.hex(8)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: role,
      status: status,
      email_verified_at: Time.current
    )
  end

  def create_announcement(
    company,
    creator,
    status: "draft",
    published_at: nil
  )
    if status == "published" || status == "archived"
      published_at ||= Time.current
    end

    Announcement.create!(
      company: company,
      created_by: creator,
      title: "Test Announcement",
      body: "This is a test announcement.",
      status: status,
      published_at: published_at
    )
  end

  def auth_headers(user)
    {
      "Authorization" => "Bearer #{TokenService.issue(user)}"
    }
  end
end
