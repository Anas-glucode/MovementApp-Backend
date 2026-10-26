class AnnouncementBroadcastJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(broadcast_id)
    broadcast = claim_broadcast(broadcast_id)
    return unless broadcast

    payload = broadcast_payload(broadcast)
    unless payload
      broadcast.update!(status: "discarded", claimed_at: nil)
      return
    end

    ActionCable.server.broadcast(
      "announcements_company_#{broadcast.company_id}",
      payload.merge(event_key: broadcast.event_key)
    )
    broadcast.update!(status: "broadcasted", broadcasted_at: Time.current, claimed_at: nil)
  rescue StandardError => error
    broadcast&.update!(status: "pending", claimed_at: nil, last_error: error.class.name)
    raise
  end

  private

  def claim_broadcast(id)
    AnnouncementBroadcast.transaction do
      broadcast = AnnouncementBroadcast.lock.find_by(id: id)
      return unless broadcast && broadcast.available_at <= Time.current
      return if broadcast.status.in?(%w[broadcasted discarded])
      return if broadcast.status == "processing" && broadcast.claimed_at > 5.minutes.ago

      broadcast.update!(status: "processing", claimed_at: Time.current)
      broadcast
    end
  end

  def broadcast_payload(broadcast)
    announcement = broadcast.announcement
    visible = announcement&.visible_at?

    case broadcast.event_type
    when "announcement_created", "announcement_updated"
      return unless visible

      {
        type: broadcast.event_type,
        announcement: announcement_payload(announcement)
      }
    when "announcement_removed"
      return if visible

      { type: broadcast.event_type, announcement_id: broadcast.announcement_reference_id }
    when "announcement_deleted"
      { type: broadcast.event_type, announcement_id: broadcast.announcement_reference_id }
    end
  end

  def announcement_payload(announcement)
    {
      id: announcement.id,
      title: announcement.title,
      message: announcement.message,
      starts_at: announcement.starts_at,
      ends_at: announcement.ends_at,
      active: announcement.active?,
      visible: announcement.visible_at?,
      created_at: announcement.created_at,
      updated_at: announcement.updated_at
    }
  end
end
