
class Activity < ApplicationRecord
  belongs_to :user
  has_one :activity_point_award, dependent: :destroy
  has_one :activity_review, dependent: :restrict_with_error
  has_many :challenge_activity_awards, dependent: :destroy

  SOURCES = %w[healthkit health_connect manual].freeze

  STATUSES = %w[pending eligible under_review rejected].freeze

  validates :activity_type, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  validates :started_at, :ended_at, presence: true
  validates :duration_seconds,
            numericality: { only_integer: true, greater_than: 0 }

  validates :steps,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_nil: true

  validates :distance_meters,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true

  validates :active_calories,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true

  validates :average_heart_rate,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 1,
              less_than_or_equal_to: 250
            },
            allow_nil: true

  validates :reported_intensity,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 1,
              less_than_or_equal_to: 10
            },
            allow_nil: true

  validates :source_record_id,
            uniqueness: { scope: [:user_id, :source] },
            allow_nil: true,
            allow_blank: true

  validate :ended_after_started

  private

  def ended_after_started
    return if started_at.blank? || ended_at.blank?
    return if ended_at > started_at

    errors.add(:ended_at, "must be after the activity start time")
  end
end
