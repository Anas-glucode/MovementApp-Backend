require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Notification Test Company",
      slug: "notification-test-#{SecureRandom.hex(4)}",
      status: "active"
    )

    @user = User.create!(
      company: @company,
      name: "Test Employee",
      email: "notification-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: "employee",
      status: "active"
    )
  end

  def build_notification(attributes = {})
    @user.notifications.build({
      notification_type: "personal_record",
      title: "New personal record",
      message: "You achieved a new running record!"
    }.merge(attributes))
  end

  test "valid notification can be created for an employee" do
    notification = build_notification

    assert notification.valid?
    assert notification.save
    assert_equal @user.id, notification.user_id
  end

  test "invalid notification type is rejected" do
    notification = build_notification(notification_type: "unknown_type")

    assert_not notification.valid?
    assert_includes notification.errors[:notification_type], "is not included in the list"
  end

  test "title is required" do
    notification = build_notification(title: nil)

    assert_not notification.valid?
  end

  test "message is required" do
    notification = build_notification(message: nil)

    assert_not notification.valid?
  end

  test "notification starts as unread" do
    notification = build_notification

    assert_nil notification.read_at
    assert_not notification.read?
  end

  test "marking notification as read records the time" do
    notification = build_notification
    notification.save!

    notification.mark_as_read!

    assert notification.read?
    assert_not_nil notification.read_at
  end

  test "marking an already read notification does not change its read time" do
    notification = build_notification
    notification.save!
    notification.mark_as_read!

    original_read_at = notification.read_at

    travel 5.minutes do
      notification.mark_as_read!
    end

    assert_equal original_read_at, notification.reload.read_at
  end

  test "unread and read scopes return the correct notifications" do
    unread_notification = build_notification
    unread_notification.save!

    read_notification = build_notification(
      title: "Another achievement"
    )
    read_notification.save!
    read_notification.mark_as_read!

    assert_includes Notification.unread, unread_notification
    assert_not_includes Notification.unread, read_notification

    assert_includes Notification.read, read_notification
    assert_not_includes Notification.read, unread_notification
  end

  test "notification can link to a related activity" do
    activity = @user.activities.create!(
      activity_type: "walking",
      source: "manual",
      status: "eligible",
      started_at: 1.hour.ago,
      ended_at: 30.minutes.ago,
      duration_seconds: 1800,
      steps: 3000,
      time_zone: "Africa/Johannesburg"
    )

    notification = build_notification(notifiable: activity)

    assert notification.valid?
    assert_equal activity, notification.notifiable
  end
end