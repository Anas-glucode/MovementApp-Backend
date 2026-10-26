require "test_helper"

class AnnouncementLifecycleTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "future announcements schedule publication and push delivery for their start" do
    start_time = 2.days.from_now.change(usec: 0)

    announcement = companies(:one).announcements.create!(
      title: "Scheduled",
      message: "Starts later",
      starts_at: start_time
    )

    created_event = announcement.announcement_broadcasts.find_by!(
      event_type: "announcement_created"
    )
    assert_equal start_time, created_event.available_at
    assert_enqueued_with(job: AnnouncementDeliveryJob, at: start_time)
  end

  test "changing a future start schedules a new publication and delivery time" do
    announcement = create_announcement(starts_at: 2.days.from_now)
    new_start = 3.days.from_now.change(usec: 0)

    assert_enqueued_with(job: AnnouncementDeliveryJob, at: new_start) do
      announcement.update!(starts_at: new_start)
    end

    assert announcement.announcement_broadcasts.exists?(
      event_type: "announcement_created",
      available_at: new_start
    )
  end

  test "editing content after creation does not enqueue another push delivery" do
    announcement = create_announcement
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AnnouncementDeliveryJob) do
      announcement.update!(message: "Edited")
    end

    assert announcement.announcement_broadcasts.exists?(event_type: "announcement_updated")
  end

  test "deactivating an announcement before delivery prevents push processing" do
    announcement = create_announcement
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AnnouncementDeliveryJob) do
      announcement.update!(active: false)
    end
  end

  private

  def create_announcement(attributes = {})
    companies(:one).announcements.create!(
      {
        title: "Lifecycle",
        message: "Announcement",
        starts_at: 1.minute.ago
      }.merge(attributes)
    )
  end
end
