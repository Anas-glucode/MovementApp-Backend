require "test_helper"

class AnnouncementBroadcastJobTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "scheduled announcement broadcasts its creation event when visible" do
    announcement = create_announcement
    event = AnnouncementBroadcast.find_by!(
      announcement: announcement,
      event_type: "announcement_created"
    )
    stream = "announcements_company_#{announcement.company_id}"

    assert_broadcasts(stream, 1) do
      AnnouncementBroadcastJob.perform_now(event.id)
    end

    assert_equal "broadcasted", event.reload.status
    message = ActiveSupport::JSON.decode(broadcasts(stream).last)
    assert_equal "announcement_created", message.fetch("type")
    assert_equal announcement.id, message.dig("announcement", "id")
    assert_equal event.event_key, message.fetch("event_key")
  end

  test "announcement updates and deletions emit lifecycle events" do
    announcement = create_announcement
    announcement.update!(title: "Updated")
    update_event = AnnouncementBroadcast.where(
      announcement: announcement,
      event_type: "announcement_updated"
    ).order(:id).last
    stream = "announcements_company_#{announcement.company_id}"

    assert_broadcasts(stream, 1) do
      AnnouncementBroadcastJob.perform_now(update_event.id)
    end
    update_message = ActiveSupport::JSON.decode(broadcasts(stream).last)
    assert_equal "announcement_updated", update_message.fetch("type")

    announcement.destroy!
    delete_event = AnnouncementBroadcast.where(
      company_id: announcement.company_id,
      event_type: "announcement_deleted"
    ).order(:id).last
    assert_not_nil delete_event
    assert_nil delete_event.announcement_id
    assert_includes delete_event.event_key, "announcement:#{announcement.id}:deleted:"

    assert_broadcasts(stream, 1) do
      AnnouncementBroadcastJob.perform_now(delete_event.id)
    end
    message = ActiveSupport::JSON.decode(broadcasts(stream).last)
    assert_equal "announcement_deleted", message.fetch("type")
    assert_equal announcement.id, message.fetch("announcement_id")
  end

  test "deactivated announcement broadcasts a removal event" do
    announcement = create_announcement
    announcement.update!(active: false)
    event = AnnouncementBroadcast.where(
      announcement: announcement,
      event_type: "announcement_removed"
    ).order(:id).last
    stream = "announcements_company_#{announcement.company_id}"

    assert_broadcasts(stream, 1) do
      AnnouncementBroadcastJob.perform_now(event.id)
    end

    message = ActiveSupport::JSON.decode(broadcasts(stream).last)
    assert_equal "announcement_removed", message.fetch("type")
    assert_equal announcement.id, message.fetch("announcement_id")
  end

  private

  def create_announcement
    companies(:one).announcements.create!(
      title: "Company announcement",
      message: "Details for employees",
      starts_at: 1.minute.ago
    )
  end
end
