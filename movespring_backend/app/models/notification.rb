class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :notifiable, polymorphic: true, optional: true

  NOTIFICATION_TYPES = %w[
    personal_record
    activity_approved
    activity_rejected
    points_awarded
    badge_earned
    challenge_update
    announcement
  ].freeze

  validates :notification_type,
            inclusion: { in: NOTIFICATION_TYPES }

  validates :title, presence: true
  validates :message, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end
end