# Adds up each team's points for ONE challenge.
# Returns a hash like { team_id => points }; a team with no points is
# simply missing from it, so callers should use .fetch(team_id, 0).
#
# Rules match the individual leaderboard: only eligible activities that
# sit fully inside the challenge dates count.
class TeamPoints
  def self.call(challenge:)
    ChallengeActivityAward
      .joins(:activity)
      # Connect each award to the activity owner's team in this challenge
      .joins(
        "INNER JOIN team_memberships " \
        "ON team_memberships.user_id = activities.user_id " \
        "AND team_memberships.challenge_id = challenge_activity_awards.challenge_id"
      )
      .where(
        challenge_id: challenge.id,
        scoring_rule_version_id: challenge.scoring_rule_version_id,
        activities: { status: "eligible" }
      )
      .where(
        "activities.started_at >= ? AND activities.ended_at <= ?",
        challenge.starts_at,
        challenge.ends_at
      )
      .group("team_memberships.team_id")
      .sum("challenge_activity_awards.points")
  end
end
