
class NotificationCreationService
  def self.call(
    user:,
    notification_type:,
    title:,
    message:,
    data: {},
    notifiable: nil
  )
    user.notifications.create!(
      notification_type: notification_type,
      title: title,
      message: message,
      data: data,
      notifiable: notifiable
    )
  end
end
