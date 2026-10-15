class DashboardSummaryService
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
    @company = user.company
    @today_range = Time.current.beginning_of_day..Time.current.end_of_day
  end

  def call
    {
      today_activity: today_activity_summary,
      challenges: active_and_upcoming_challenges,
      rankings: personal_rankings,
      recent_achievements: recent_achievements_summary
    }
  end

  private

  attr_reader :user, :company, :today_range

  def today_activity_summary
    today_activities = user.activities.where(started_at: today_range)

    # Sum verified or eligible activities
    valid_activities = today_activities.where(status: %w[eligible approved])

    total_steps = valid_activities.sum(:steps) || 0
    total_calories = valid_activities.sum(:active_calories) || 0
    total_duration_seconds = valid_activities.sum(:duration_seconds) || 0

    # Calculate points earned today through awards
    total_points = ActivityPointAward
      .joins(:activity)
      .where(activities: { user_id: user.id, started_at: today_range })
      .sum(:points) || 0

    {
      steps: total_steps,
      active_calories: total_calories.round(1),
      active_minutes: (total_duration_seconds / 60.0).round,
      points: total_points,
      last_synced_at: user.activities.maximum(:created_at)&.iso8601
    }
  end

  def active_and_upcoming_challenges
    participations = user.challenge_participations
                         .includes(:challenge)
                         .joins(:challenge)
                         .where(challenges: { status: %w[published active] })
                         .order("challenges.starts_at ASC")

    participations.map do |participation|
      challenge = participation.challenge
      {
        id: challenge.id,
        name: challenge.name,
        status: challenge.status,
        starts_at: challenge.starts_at.iso8601,
        ends_at: challenge.ends_at.iso8601,
        joined_at: participation.created_at.iso8601
      }
    end
  end

  def personal_rankings
    # Baseline structure ready for full leaderboard module hookup
    active_challenges = user.joined_challenges.where(status: "active")

    active_challenges.map do |challenge|
      # Fetch total points earned by user within challenge date bounds
      user_points = ActivityPointAward
        .joins(:activity)
        .where(activities: { user_id: user.id, started_at: challenge.starts_at..challenge.ends_at })
        .sum(:points) || 0

      {
        challenge_id: challenge.id,
        challenge_name: challenge.name,
        user_points: user_points,
        rank: calculate_user_rank(challenge, user_points)
      }
    end
  end

  def calculate_user_rank(challenge, user_points)
    # Simple rank calculation relative to other participants
    higher_scores = ActivityPointAward
      .joins(:activity)
      .where(activities: { user_id: challenge.participant_ids, started_at: challenge.starts_at..challenge.ends_at })
      .group("activities.user_id")
      .having("SUM(activity_point_awards.points) > ?", user_points)
      .length

    higher_scores + 1
  end

  def recent_achievements_summary
    # Plugs into badges/personal records when available
    {
      badges_count: 0,
      latest_badge: nil
    }
  end
end