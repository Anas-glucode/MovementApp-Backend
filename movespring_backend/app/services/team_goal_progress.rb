# Turns "this team has N points" into thermometer fields for the app.
# Returns nil when the challenge has no goal, so the JSON can say
# "goal": null and the app knows not to draw a progress bar.
class TeamGoalProgress
  def self.call(challenge:, points:)
    goal = challenge.team_goal_points
    return nil if goal.blank?

    {
      goal_points: goal,
      # How many points are still needed. Never negative.
      points_remaining: [goal - points, 0].max,
      # Can exceed 100 (a team on 6,000 of 5,000 shows 120.0)
      percent: ((points.to_f / goal) * 100).round(1),
      # A simple true/false for the "you did it!" moment
      goal_reached: points >= goal
    }
  end
end
