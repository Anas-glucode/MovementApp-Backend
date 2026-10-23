# Builds the individual leaderboard for ONE challenge, with ranks.
#
# Rules:
#   * an activity counts if it is eligible and STARTED inside the challenge
#   * deactivated people are left out (they return if reactivated, because
#     nothing is deleted)
#   * ties share a rank (1, 1, 3), like a dead heat in a race
class ChallengeLeaderboard
  def self.call(challenge:)
    new(challenge).call
  end

  def initialize(challenge)
    @challenge = challenge
  end

  def call
    participations = @challenge.challenge_participations
                               .includes(:user)
                               .to_a
                               .select { |participation| participation.user.active? }

    user_ids = participations.map(&:user_id)
    points_by_user = points_for(user_ids)

    entries = participations.map do |participation|
      {
        user_id: participation.user.id,
        name: participation.user.name,
        points: points_by_user.fetch(participation.user_id, 0)
      }
    end

    entries.sort_by! { |entry| [-entry[:points], entry[:name].downcase] }

    previous_points = nil
    current_rank = 0

    entries.each_with_index do |entry, index|
      if entry[:points] != previous_points
        current_rank = index + 1
        previous_points = entry[:points]
      end

      entry[:rank] = current_rank
    end

    entries
  end

  private

  def points_for(user_ids)
    return {} if user_ids.empty?

    ChallengeActivityAward
      .joins(:activity)
      .where(
        challenge_id: @challenge.id,
        scoring_rule_version_id: @challenge.scoring_rule_version_id
      )
      .where(
        activities: {
          user_id: user_ids,
          status: "eligible",
          started_at: @challenge.window
        }
      )
      .group("activities.user_id")
      .sum(:points)
  end
end
