class PersonalRecordEvent < ApplicationRecord
  belongs_to :user
  belongs_to :activity, optional: true

  RECORD_TYPES = %w[
    longest_run
    longest_cycling_distance
    longest_workout
    highest_daily_steps
    most_active_minutes
    highest_daily_points
    highest_weekly_points
    longest_streak
  ].freeze

  validates :record_type, inclusion: { in: RECORD_TYPES }

  validates :new_value,
            numericality: { greater_than_or_equal_to: 0 }

  validates :previous_value,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true

  validates :achieved_at, presence: true

  validate :new_value_must_improve_previous_value
  validate :activity_must_belong_to_same_user

  private

  def activity_must_belong_to_same_user
  return if activity.nil? || user.nil?
  return if activity.user_id == user_id

  errors.add(:activity, "must belong to the same user")
end

  def new_value_must_improve_previous_value
    return if previous_value.nil?
    return if new_value.nil?
    return if new_value > previous_value

    errors.add(:new_value, "must be greater than the previous record")
  end
end