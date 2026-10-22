# A "does this add up?" check, like a cashier holding a banknote up to the
# light. It looks at the NUMBERS on an activity (distance, steps, calories,
# heart rate) and asks whether they are physically believable for the time
# taken. It never touches the database and never saves anything.
#
# Returns a short reason string if something looks wrong (an admin should
# look), or nil if everything looks fine.
#
# The limits are deliberately generous: they exist to catch "ran 80 km in
# 20 minutes", not to punish fast athletes. Tune them as you see real data.
class ActivityPlausibilityChecker
  # Top sustained speeds in metres per second (3.0 m/s is about 10.8 km/h).
  # Sports not listed here (football, golf, strength) have no distance check.
  MAX_SPEED_METERS_PER_SECOND = {
    "walking" => 3.0,
    "running" => 8.0,
    "cycling" => 20.0,
    "swimming" => 2.0
  }.freeze

  MAX_STEPS_PER_MINUTE = 250
  MAX_CALORIES_PER_MINUTE = 40
  MIN_HEART_RATE = 30

  def self.call(activity:)
    new(activity).call
  end

  def initialize(activity)
    @activity = activity
  end

  def call
    return "Heart rate looks implausible" if heart_rate_implausible?
    return "Distance is too large for the time taken" if too_fast?
    return "Step count is too high for the time taken" if too_many_steps?
    return "Calories are too high for the time taken" if too_many_calories?

    nil
  end

  private

  def minutes
    @activity.duration_seconds / 60.0
  end

  def heart_rate_implausible?
    rate = @activity.average_heart_rate
    rate.present? && rate < MIN_HEART_RATE
  end

  def too_fast?
    max_speed = MAX_SPEED_METERS_PER_SECOND[@activity.activity_type]
    return false unless max_speed && @activity.distance_meters.present?

    (@activity.distance_meters.to_f / @activity.duration_seconds) > max_speed
  end

  def too_many_steps?
    return false if @activity.steps.blank?

    (@activity.steps / minutes) > MAX_STEPS_PER_MINUTE
  end

  def too_many_calories?
    return false if @activity.active_calories.blank?

    (@activity.active_calories.to_f / minutes) > MAX_CALORIES_PER_MINUTE
  end
end