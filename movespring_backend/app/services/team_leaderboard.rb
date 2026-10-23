# Builds the team leaderboard for ONE challenge: one entry per team, best
# team first, with ranks.
#
# How teams are ranked depends on the challenge's team_scoring_method:
#   "average" -> points per team member (fair when team sizes differ)
#   "total"   -> everyone's points added together
#
# Only ACTIVE members count, in the headcount and in the points
# (see TeamPoints). Someone who leaves the company stops affecting the
# average, and comes back if they are reactivated.
#
# It lives here, not in the controller, so it can be tested on its own.
class TeamLeaderboard
  def self.call(challenge:)
    new(challenge).call
  end

  def initialize(challenge)
    @challenge = challenge
  end

  def call
    teams = @challenge.teams.includes(:members).order(:id).to_a
    points_by_team = TeamPoints.call(challenge: @challenge)

    # Pair every entry with its ranking score. The score is kept OUT of the
    # entry itself so it can stay exact (see exact_average below).
    scored = teams.map do |team|
      member_count = team.members.select(&:active?).size
      points = points_by_team.fetch(team.id, 0)

      [
        build_entry(team, member_count, points),
        ranking_score(points, member_count)
      ]
    end

    # Best score first; ties broken by name so the order is stable.
    scored.sort_by! { |entry, score| [-score, entry[:name].downcase] }

    # Tied teams share a rank (1, 1, 3), like a dead heat in a race.
    previous_score = nil
    current_rank = 0

    scored.each_with_index do |(entry, score), index|
      if score != previous_score
        current_rank = index + 1
        previous_score = score
      end

      entry[:rank] = current_rank
    end

    scored.map(&:first)
  end

  private

  def build_entry(team, member_count, points)
    {
      team_id: team.id,
      name: team.name,
      member_count: member_count,
      points: points,
      average_points: average_for_display(points, member_count),
      # nil when the challenge has no goal
      goal: TeamGoalProgress.call(challenge: @challenge, points: points)
    }
  end

  def ranking_score(points, member_count)
    if @challenge.team_scoring_method == "total"
      points
    else
      exact_average(points, member_count)
    end
  end

  # Rational keeps the division EXACT: 100000/10 and 50000/5 are really equal.
  # With ordinary decimals, tiny rounding errors could break a genuine tie.
  def exact_average(points, member_count)
    member_count.zero? ? Rational(0) : Rational(points, member_count)
  end

  def average_for_display(points, member_count)
    exact_average(points, member_count).to_f.round(1)
  end
end