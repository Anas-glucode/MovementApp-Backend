# Puts ONE person onto the smallest team of a team challenge.
# Used when someone joins after the teams were already dealt.
#
# Returns the team they landed on, or nil when there is nothing to do
# (not a team challenge, or teams have not been formed yet).
class TeamAssignmentService
  def self.call(challenge:, user:)
    new(challenge: challenge, user: user).call
  end

  def initialize(challenge:, user:)
    @challenge = challenge
    @user = user
  end

  def call
    return nil unless @challenge.team?

    # Lock the challenge row so two people joining at the same instant
    # cannot both look at the table and pick the same "smallest" team.
    @challenge.with_lock do
      # Already on a team? Do nothing (safe to call twice)
      existing = TeamMembership.find_by(challenge_id: @challenge.id, user_id: @user.id)
      return existing.team if existing

      # Teams not formed yet: the admin's "form teams" step will deal them in
      return nil unless @challenge.teams.exists?

      # Count members per team, fewest first. Ties go to the lowest id.
      # left_joins keeps teams that have zero members in the list.
      smallest = @challenge.teams
                           .left_joins(:team_memberships)
                           .group("teams.id")
                           .order(Arel.sql("COUNT(team_memberships.id) ASC, teams.id ASC"))
                           .first

      smallest.team_memberships.create!(user: @user, challenge: @challenge)
      smallest
    end
  end
end
