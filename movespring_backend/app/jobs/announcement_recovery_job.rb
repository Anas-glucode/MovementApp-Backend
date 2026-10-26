class AnnouncementRecoveryJob < ApplicationJob
  queue_as :default

  def perform
    recover_stale_broadcasts
    recover_due_broadcasts
    recover_due_announcements
    recover_pending_deliveries
    mark_abandoned_deliveries
  end

  private

  def recover_stale_broadcasts
    AnnouncementBroadcast.where(status: "processing")
                         .where("claimed_at < ?", 10.minutes.ago)
                         .update_all(
                           status: "pending",
                           claimed_at: nil,
                           last_error: "Recovered after interrupted broadcast",
                           updated_at: Time.current
                         )
  end

  def recover_due_broadcasts
    AnnouncementBroadcast.where(status: "pending")
                         .where("available_at <= ?", Time.current)
                         .find_each do |broadcast|
      AnnouncementBroadcastJob.perform_later(broadcast.id)
    end
  end

  def recover_due_announcements
    Announcement.visible_at
                 .where(delivery_prepared_at: nil)
                 .find_each do |announcement|
      AnnouncementDeliveryJob.perform_later(announcement.id)
    end
  end

  def recover_pending_deliveries
    AnnouncementDelivery.where(status: "pending")
                        .distinct
                        .pluck(:announcement_id)
                        .each do |announcement_id|
      AnnouncementDeliveryJob.perform_later(announcement_id)
    end
  end

  def mark_abandoned_deliveries
    AnnouncementDelivery.where(status: "processing")
                        .where("claimed_at < ?", 10.minutes.ago)
                        .update_all(
                          status: "unknown",
                          claimed_at: nil,
                          last_error: "Worker stopped before saving the provider result",
                          updated_at: Time.current
                        )
  end
end
