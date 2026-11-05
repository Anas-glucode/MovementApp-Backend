class AnnouncementPublishingService
  class InvalidTransition < StandardError; end

  def self.call(announcement:)
    Announcement.transaction do
      announcement.with_lock do
        unless announcement.draft?
          raise InvalidTransition, "Only draft announcements can be published"
        end

        announcement.update!(
          status: "published",
          published_at: Time.current
        )

        employees = announcement.company.users.where(
          role: "employee",
          status: "active"
        )

        employees.find_each do |employee|
          NotificationCreationService.call(
            user: employee,
            notification_type: "announcement",
            title: announcement.title,
            message: announcement.body,
            data: { announcement_id: announcement.id },
            notifiable: announcement
          )
        end
      end
    end

    announcement
  end
end
