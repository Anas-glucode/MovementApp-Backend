class AnnouncementDelivery < ApplicationRecord
  belongs_to :announcement
  belongs_to :push_token, optional: true
  belongs_to :user

  STATUSES = %w[pending processing delivered failed unknown].freeze

  validates :status, inclusion: { in: STATUSES }
end
