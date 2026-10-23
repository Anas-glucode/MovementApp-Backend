# A person's personal bests (requirement 12), worked out from their
# ELIGIBLE activities only. A rejected or still-pending activity never
# counts toward a record.
#
# The first four keys are per single activity and keep their old names so
# nothing that already reads them breaks. The rest are new:
# per-day totals, longest run and ride, points records and streaks.
#
# Distances are returned as plain numbers (not BigDecimal), because Rails
# turns BigDecimal into a STRING in JSON ("12000.0"), which is awkward for
# the app.
class PersonalRecords
  def self.call(user:)
    new(user).call
  end

  def initialize(user)
    @user = user
  end

  def call
    rows = @user.activities
                .where(status: "eligible")
                .pluck(:started_at, :activity_type, :steps, :distance_meters,
                       :duration_seconds, :active_calories)

    steps_by_day = Hash.new(0)
    seconds_by_day = Hash.new(0)
    best = Hash.new(0)

    rows.each do |started_at, type, steps, distance, duration, calories|
      day = local_date(started_at)

      steps_by_day[day] += steps.to_i
      seconds_by_day[day] += duration.to_i

      best[:steps] = [best[:steps], steps.to_i].max
      best[:distance] = [best[:distance], distance.to_f].max
      best[:duration] = [best[:duration], duration.to_i].max
      best[:calories] = [best[:calories], calories.to_f].max
      best[:run] = [best[:run], distance.to_f].max if type == "running"
      best[:cycle] = [best[:cycle], distance.to_f].max if type == "cycling"
    end

    points_by_day, points_by_week = points_totals
    streaks = ActivityStreaks.call(user: @user)

    {
      # per single activity (old names kept)
      max_steps: best[:steps],
      max_distance_meters: best[:distance].round(1),
      max_duration_seconds: best[:duration],
      max_active_calories: best[:calories].round(1),

      # per day
      max_steps_in_a_day: steps_by_day.values.max || 0,
      max_active_seconds_in_a_day: seconds_by_day.values.max || 0,

      # by sport
      longest_run_meters: best[:run].round(1),
      longest_cycling_meters: best[:cycle].round(1),

      # points
      max_points_in_a_day: points_by_day.values.max || 0,
      max_points_in_a_week: points_by_week.values.max || 0,

      # streaks
      longest_streak_days: streaks[:longest_daily],
      current_streak_days: streaks[:current_daily],
      longest_weekly_streak: streaks[:longest_weekly],
      active_days: streaks[:active_days]
    }
  end

  private

  def zone
    name = @user.company&.time_zone.presence

    (name && ActiveSupport::TimeZone[name]) || ActiveSupport::TimeZone["UTC"]
  end

  def local_date(time)
    time.in_time_zone(zone).to_date
  end

  # Points per local day and per local week (weeks start on Monday)
  def points_totals
    by_day = Hash.new(0)
    by_week = Hash.new(0)

    ActivityPointAward
      .joins(:activity)
      .where(activities: { user_id: @user.id, status: "eligible" })
      .pluck("activities.started_at", "activity_point_awards.points")
      .each do |started_at, points|
      day = local_date(started_at)

      by_day[day] += points
      by_week[day.beginning_of_week] += points
    end

    [by_day, by_week]
  end
end
