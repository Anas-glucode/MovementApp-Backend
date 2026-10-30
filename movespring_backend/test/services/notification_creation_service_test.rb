
require "test_helper"

class NotificationCreationServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Notification Service Company",
      slug: "notification-service-#{SecureRandom.hex(4)}",
      status: "active"
    )

    @user = User.create!(
      company: @company,
      name: "Test Employee",
      email: "notification-service-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: "employee",
      status: "active"
    )
  end

  test "creates a notification for the specified user" do
    notification = NotificationCreationService.call(
      user: @user,
      notification_type: "badge_earned",
      title: "New badge earned",
      message: "You earned the Walking Champion badge!"
    )

    assert notification.persisted?
    assert_equal @user.id, notification.user_id
    assert_equal "badge_earned", notification.notification_type
    assert_equal "New badge earned", notification.title
    assert_equal "You earned the Walking Champion badge!", notification.message
  end

  test "stores additional data on the notification" do
    notification = NotificationCreationService.call(
      user: @user,
      notification_type: "activity_approved",
      title: "Activity approved",
      message: "Your walking activity was approved.",
      data: { activity_id: 123 }
    )

    assert_equal(
      { "activity_id" => 123 },
      notification.data
    )
  end

  test "links the notification to a related record" do
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

    notification = NotificationCreationService.call(
      user: @user,
      notification_type: "activity_approved",
      title: "Activity approved",
      message: "Your activity was approved.",
      notifiable: activity
    )

    assert_equal activity, notification.notifiable
  end

  test "rejects an invalid notification type" do
    assert_raises(ActiveRecord::RecordInvalid) do
      NotificationCreationService.call(
        user: @user,
        notification_type: "unknown_type",
        title: "Invalid notification",
        message: "This should not be saved."
      )
    end
  end
end
