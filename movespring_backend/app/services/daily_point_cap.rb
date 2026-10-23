# A daily allowance on points. Like a daily spending limit on a bank card:
# each local day a person can earn up to the limit, and once it is spent,
# further activities that day still get recorded but earn 0 points.
#
# This class only does the arithmetic and works out the day. The scoring
# services use it, and they do the database lookups and saving.
class DailyPointCap
  # Used when a scoring-rules version does not set its own "daily_point_cap".
  # To change the default for everyone, change this one number.
  DEFAULT_CAP = 500

  # The cap for a set of scoring rules (the rules can override the default)
  def self.limit_for(rules)
    rules.fetch("daily_point_cap", DEFAULT_CAP).to_i
  end

  # How many points the activity may earn, given how many the person already
  # earned that day. Never negative, and never more than it earned on merit.
  def self.apply(points:, activity:, rules:, already_awarded:)
    remaining = [limit_for(rules) - already_awarded, 0].max
    [points, remaining].min
  end

  # The whole local day this activity belongs to: midnight to midnight in the
  # COMPANY's time zone. An activity counts toward the day it STARTED.
  #
  # CHANGED: this used to trust the time zone the phone sent. Someone could
  # send a different zone on each activity and turn one real day into two
  # capped days. The company's zone is set by an administrator, so it can't
  # be played with from the client.
  def self.day_range(activity)
    activity.started_at.in_time_zone(zone_for(activity)).all_day
  end

  # The company's zone, falling back to UTC if it is missing or unrecognised.
  def self.zone_for(activity)
    zone_name = activity.user&.company&.time_zone.presence

    (zone_name && ActiveSupport::TimeZone[zone_name]) ||
      ActiveSupport::TimeZone["UTC"]
  end
end