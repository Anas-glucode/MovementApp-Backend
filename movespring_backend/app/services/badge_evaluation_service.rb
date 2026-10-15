class BadgeEvaluationService
  def initialize(user, activity = nil)
    @user = user
    @activity = activity
    @newly_awarded = []
  end

  def call
    evaluate_badges
    {
      newly_awarded_badges: @newly_awarded,
      personal_records: personal_records
    }
  end

  private

  def evaluate_badges
    available_badges = Badge.where(company_id: [nil, @user.company_id])
                            .where.not(id: @user.badge_ids)

    available_badges.each do |badge|
      award_badge(badge) if criteria_met?(badge)
    end
  end

  def criteria_met?(badge)
    case badge.criteria_type
    when "single_activity"
      return false unless @activity

      case badge.category
      when "milestone"
        @user.activities.count >= badge.criteria_value
      when "steps"
        (@activity.steps || 0) >= badge.criteria_value
      when "distance"
        (@activity.distance_meters || 0) >= badge.criteria_value
      when "duration"
        (@activity.duration_seconds || 0) >= badge.criteria_value
      else
        false
      end
    when "cumulative"
      case badge.category
      when "steps"
        @user.activities.sum(:steps) >= badge.criteria_value
      when "distance"
        @user.activities.sum(:distance_meters) >= badge.criteria_value
      when "duration"
        @user.activities.sum(:duration_seconds) >= badge.criteria_value
      else
        false
      end
    else
      false
    end
  end

  def award_badge(badge)
    user_badge = @user.user_badges.create!(
      badge: badge,
      activity: @activity,
      earned_at: Time.current
    )
    @newly_awarded << user_badge
  rescue ActiveRecord::RecordInvalid

  end

  def personal_records
    user_activities = @user.activities

    {
      max_steps: user_activities.maximum(:steps) || 0,
      max_distance_meters: user_activities.maximum(:distance_meters) || 0,
      max_duration_seconds: user_activities.maximum(:duration_seconds) || 0,
      max_active_calories: user_activities.maximum(:active_calories) || 0
    }
  end
end