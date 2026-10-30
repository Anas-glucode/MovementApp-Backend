# Works out a person's activity streaks.
#
# A day counts as an "active day" when their ELIGIBLE activities that day add
# up to at least MIN_ACTIVE_SECONDS_PER_DAY (10 minutes). Without a minimum,
# logging a one-minute walk every day would keep a streak alive. Change the
# number below if you want it stricter or looser.
#
# "Day" means the day in the COMPANY's time zone, the same as the daily point
# cap, so streaks and caps never disagree about when midnight is.
class ActivityStreaks
  MIN_ACTIVE_SECONDS_PER_DAY = 10 * 60

  def self.call(user:, excluding_activity_id: nil)
    new(user, excluding_activity_id: excluding_activity_id).call
  end

  def initialize(user, excluding_activity_id: nil)
    @user = user
    @excluding_activity_id = excluding_activity_id
  end

  def call
    dates = active_dates

    {
      longest_daily: longest_run(dates, 1),
      current_daily: current_run(dates),
      longest_weekly: longest_run(dates.map(&:beginning_of_week).uniq, 7),
      active_days: dates.size
    }
  end

  private

  def zone
    name = @user.company&.time_zone.presence

    (name && ActiveSupport::TimeZone[name]) || ActiveSupport::TimeZone["UTC"]
  end

  # The sorted list of days that count as active
  def active_dates
    seconds_by_date = Hash.new(0)

    activities = @user.activities.where(status: "eligible")
    if @excluding_activity_id.present?
      activities = activities.where.not(id: @excluding_activity_id)
    end

    activities.pluck(:started_at, :duration_seconds)
         .each do |started_at, duration|
      seconds_by_date[started_at.in_time_zone(zone).to_date] += duration.to_i
    end

    seconds_by_date.select { |_date, seconds| seconds >= MIN_ACTIVE_SECONDS_PER_DAY }
                   .keys
                   .sort
  end

  # The longest chain where each value follows the last by exactly `step`
  # days (1 for days in a row, 7 for weeks in a row).
  def longest_run(values, step)
    best = 0
    run = 0
    previous = nil

    values.each do |value|
      run = previous && value == previous + step ? run + 1 : 1
      best = [best, run].max
      previous = value
    end

    best
  end

  # The streak that is still alive. Not having logged TODAY yet doesn't break
  # it: it only ends once a whole day has passed with nothing.
  def current_run(dates)
    return 0 if dates.empty?

    today = Time.current.in_time_zone(zone).to_date
    return 0 if dates.last < today - 1

    run = 1

    dates.reverse.each_cons(2) do |later, earlier|
      break unless earlier == later - 1

      run += 1
    end

    run
  end
end
