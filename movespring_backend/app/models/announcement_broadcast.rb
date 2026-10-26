class AnnouncementBroadcast < ApplicationRecord
  belongs_to :announcement, optional: true
  belongs_to :company

  STATUSES = %w[pending processing broadcasted discarded].freeze

  validates :event_key, :event_type, :available_at, presence: true
  validates :event_key, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
end
