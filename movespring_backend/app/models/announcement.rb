class Announcement < ApplicationRecord
  belongs_to :company
  has_many :announcement_dismissals, dependent: :destroy

  validates :title, presence: true, length: { maximum: 150 }
  validates :message, presence: true, length: { maximum: 5_000 }
  validates :starts_at, presence: true
  validate :ends_after_starts

  scope :visible_at, ->(time = Time.current) {
    where(active: true)
      .where("starts_at <= ?", time)
      .where("ends_at IS NULL OR ends_at > ?", time)
  }

  def visible_at?(time = Time.current)
    active? && starts_at <= time && (ends_at.nil? || ends_at > time)
  end

  private

  def ends_after_starts
    return if ends_at.blank? || starts_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after the start time")
  end
end
