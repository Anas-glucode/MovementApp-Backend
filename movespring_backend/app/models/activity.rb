class Activity < ApplicationRecord
  belongs_to :user
  has_one :activity_point_award, dependent: :destroy
  has_one :activity_review, dependent: :restrict_with_error
  has_many :challenge_activity_awards, dependent: :destroy
  has_many :personal_record_events, dependent: :nullify

  SOURCES = %w[healthkit health_connect manual].freeze

  STATUSES = %w[pending eligible under_review rejected].freeze

  # The ONE list of sports the app understands. The service, the scoring-rule
  # validation and the database check constraint all use this same list, so
  # adding a sport means changing it here (plus a new migration for the
  # constraint) and nowhere else.
  TYPES = %w[
    walking
    running
    cycling
    swimming
    football
    strength_training
    golf
  ].freeze

  validates :activity_type, presence: true, inclusion: { in: TYPES }
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
  validate :time_zone_must_be_recognised

  def manual?
    source == "manual"
  end

  # An honest label for the app to show next to the activity.
  # We can never PROVE a phone really read HealthKit (a modified app could
  # lie), so we say "device_reported", not "verified".
  def verification
    manual? ? "self_reported" : "device_reported"
  end

  private

  def ended_after_started
    return if started_at.blank? || ended_at.blank?
    return if ended_at > started_at

    errors.add(:ended_at, "must be after the activity start time")
  end

  # A made-up time zone used to be silently treated as UTC. Now it is an error,
  # because the time zone decides which "day" the daily point cap uses.
  def time_zone_must_be_recognised
    return if time_zone.blank?
    return if ActiveSupport::TimeZone[time_zone].present?

    errors.add(:time_zone, "is not a recognised time zone")
  end
end