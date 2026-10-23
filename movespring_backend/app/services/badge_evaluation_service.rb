# Decides which badges a person has now earned.
#
#   BadgeEvaluationService.new(user, activity).evaluate
#
# What changed from the old version:
#   * only ELIGIBLE activities count. Before, a rejected or still-pending
#     activity could earn a badge, which is the same loophole the points
#     rules already closed.
#   * checking for badges no longer happens when someone merely VIEWS their
#     badges. Reading should never change anything.
#   * the totals are worked out once, not once per badge.
#   * streak badges (daily_streak, weekly_streak) are understood.
#   * two parallel checks can no longer crash each other (see award_badge).
class BadgeEvaluationService
  # Awards badges for everything a person did BEFORE badges were switched on.
  # Run it through:  bin/rails badges:backfill
  def self.backfill(user)
    user.activities.where(status: "eligible").order(:started_at, :id).each do |activity|
      new(user, activity).evaluate
    end

    new(user).evaluate
  end

  def initialize(user, activity = nil)
    @user = user
    @activity = activity
    @newly_awarded = []
    @totals = {}
  end

  # Kept for existing callers: awards badges AND returns the personal records.
  def call
    evaluate

    {
      newly_awarded_badges: @newly_awarded,
      personal_records: PersonalRecords.call(user: @user)
    }
  end

  # Awards any newly earned badges and returns them.
  def evaluate
    return @newly_awarded unless activity_can_count?

    available_badges.each do |badge|
      award_badge(badge) if criteria_met?(badge)
    end

    @newly_awarded
  end

  private

  # An activity that is not eligible (rejected, under review) earns nothing
  def activity_can_count?
    return true if @activity.nil?

    @activity.user_id == @user.id && @activity.status == "eligible"
  end

  # Global badges plus this company's own, minus the ones already earned
  def available_badges
    Badge.where(company_id: [nil, @user.company_id])
         .where.not(id: UserBadge.where(user_id: @user.id).select(:badge_id))
  end

  def criteria_met?(badge)
    target = badge.criteria_value

    case badge.criteria_type
    when "single_activity" then single_activity_met?(badge.category, target)
    when "cumulative" then cumulative_met?(badge.category, target)
    when "daily_streak" then streaks[:longest_daily] >= target
    when "weekly_streak" then streaks[:longest_weekly] >= target
    else false
    end
  end

  # One activity on its own reaches the target. Needs an activity to look at.
  def single_activity_met?(category, target)
    return false unless @activity

    case category
    when "milestone" then eligible_activities.count >= target
    when "steps" then (@activity.steps || 0) >= target
    when "distance" then (@activity.distance_meters || 0) >= target
    when "duration" then (@activity.duration_seconds || 0) >= target
    else false
    end
  end

  # Everything added up reaches the target
  def cumulative_met?(category, target)
    column = { "steps" => :steps,
               "distance" => :distance_meters,
               "duration" => :duration_seconds }[category]
    return false unless column

    # Worked out once per category, however many badges use it
    @totals[column] ||= eligible_activities.sum(column)
    @totals[column] >= target
  end

  def eligible_activities
    @user.activities.where(status: "eligible")
  end

  def streaks
    @streaks ||= ActivityStreaks.call(user: @user)
  end

  # A savepoint (requires_new) keeps a "duplicate" failure from poisoning any
  # bigger transaction this might run inside. If the badge was already earned,
  # for example by a parallel request a moment ago, that is fine: do nothing.
  def award_badge(badge)
    user_badge = UserBadge.transaction(requires_new: true) do
      UserBadge.create!(
        user: @user,
        badge: badge,
        activity: @activity,
        earned_at: Time.current
      )
    end

    @newly_awarded << user_badge
    user_badge
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    nil
  end
end