require "test_helper"
require "securerandom"

class AnnouncementPublishingServiceTest < ActiveSupport::TestCase
  setup do
    @company = create_company("Announcement Company")

    @admin = create_user(@company, "company_admin")
    @employee = create_user(@company, "employee")
    @inactive_employee = create_user(@company, "employee", status: "inactive")

    @other_company = create_company("Other Company")
    @other_employee = create_user(@other_company, "employee")

    @announcement = Announcement.create!(
      company: @company,
      created_by: @admin,
      title: "Important Company Update",
      body: "We have an important update for everyone.",
      status: "draft"
    )
  end

  test "publishes a draft announcement" do
    AnnouncementPublishingService.call(announcement: @announcement)

    assert @announcement.reload.published?
    assert_not_nil @announcement.published_at
  end

  test "creates notifications for active employees in the same company" do
    AnnouncementPublishingService.call(announcement: @announcement)

    notification = @employee.notifications.find_by!(
      notifiable: @announcement
    )

    assert_equal "announcement", notification.notification_type
    assert_equal @announcement.title, notification.title
    assert_equal @announcement.body, notification.message
  end

  test "does not notify inactive employees or employees in another company" do
    AnnouncementPublishingService.call(announcement: @announcement)

    assert_equal 0, @inactive_employee.notifications.count
    assert_equal 0, @other_employee.notifications.count
  end

  test "does not publish an announcement more than once" do
    AnnouncementPublishingService.call(announcement: @announcement)

    assert_raises(AnnouncementPublishingService::InvalidTransition) do
      AnnouncementPublishingService.call(announcement: @announcement)
    end

    assert_equal 1, @employee.notifications.where(
      notifiable: @announcement
    ).count
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
      name: "Test #{role}",
      email: "#{role}-#{SecureRandom.hex(8)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: role,
      status: status,
      email_verified_at: Time.current
    )
  end
end
