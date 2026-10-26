class Announcement < ApplicationRecord
  belongs_to :company
  has_many :announcement_dismissals, dependent: :destroy
  has_many :announcement_comments, dependent: :destroy
  has_many :announcement_deliveries, dependent: :destroy
  has_many :announcement_broadcasts, dependent: :nullify

  validates :title, presence: true, length: { maximum: 150 }
  validates :message, presence: true, length: { maximum: 5_000 }
  validates :starts_at, presence: true
  validate :ends_after_starts
  after_create_commit :schedule_publication
  after_update_commit :schedule_lifecycle_changes
  after_destroy_commit :broadcast_deletion

  scope :visible_at, ->(time = Time.current) {
    where(active: true)
      .where("starts_at <= ?", time)
      .where("ends_at IS NULL OR ends_at > ?", time)
  }

  def visible_at?(time = Time.current)
    active? && starts_at <= time && (ends_at.nil? || ends_at > time)
  end

  private

  def schedule_publication
    return unless active?

    enqueue_lifecycle_broadcast("announcement_created", "created", starts_at)
    enqueue_delivery
    enqueue_expiration
  end

  def schedule_lifecycle_changes
    relevant_changes = %w[active starts_at ends_at title message]
    return if (saved_changes.keys & relevant_changes).empty?

    if visible_at?
      was_visible = previous_visibility
      enqueue_lifecycle_broadcast(
        was_visible ? "announcement_updated" : "announcement_created",
        "updated:#{updated_at.to_f}",
        Time.current
      )
    elsif previous_visibility
      enqueue_lifecycle_broadcast(
        "announcement_removed",
        "removed:#{updated_at.to_f}",
        Time.current
      )
    elsif active? && (saved_change_to_active? || saved_change_to_starts_at?)
      enqueue_lifecycle_broadcast(
        "announcement_created",
        "rescheduled:#{updated_at.to_f}",
        starts_at
      )
    end

    delivery_timing_changed = (saved_changes.keys & %w[active starts_at ends_at]).any?
    if active? && delivery_timing_changed
      enqueue_delivery
      enqueue_expiration if saved_change_to_active? || saved_change_to_ends_at?
    end
  end

  def broadcast_deletion
    enqueue_lifecycle_broadcast(
      "announcement_deleted",
      "deleted:#{updated_at.to_f}",
      Time.current,
      announcement_id: nil,
      company_id: company_id,
      key_id: id
    )
  end

  def enqueue_lifecycle_broadcast(event_type, event_key_suffix, available_at,
                                  announcement_id: id, company_id: self.company_id,
                                  key_id: announcement_id)
    event = AnnouncementBroadcast.create_or_find_by!(
      event_key: "announcement:#{key_id}:#{event_key_suffix}"
    ) do |record|
      record.announcement_id = announcement_id
      record.announcement_reference_id = key_id
      record.company_id = company_id
      record.event_type = event_type
      record.available_at = available_at
    end

    AnnouncementBroadcastJob.set(wait_until: [ available_at, Time.current ].max)
                            .perform_later(event.id) if event.status == "pending"
  end

  def enqueue_delivery
    return unless active?

    AnnouncementDeliveryJob.set(wait_until: [ starts_at, Time.current ].max)
                           .perform_later(id)
  end

  def enqueue_expiration
    return unless ends_at&.future?

    enqueue_lifecycle_broadcast(
      "announcement_removed",
      "expires:#{ends_at.to_f}",
      ends_at
    )
  end

  def previous_visibility
    old_active = saved_change_to_active? ? saved_change_to_active.first : active?
    old_start = saved_change_to_starts_at? ? saved_change_to_starts_at.first : starts_at
    old_end = saved_change_to_ends_at? ? saved_change_to_ends_at.first : ends_at

    old_active && old_start <= Time.current && (old_end.nil? || old_end > Time.current)
  end

  def ends_after_starts
    return if ends_at.blank? || starts_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after the start time")
  end
end
