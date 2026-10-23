# app/services/team_formation_service.rb
#
# Deals the people who joined a team challenge into teams, like dealing
# cards: shuffle everyone, then hand them out one by one in a circle.
# That keeps team sizes within one person of each other.
class TeamFormationService
  MIN_TEAMS = 2

  def self.call(challenge:, team_count: nil, team_size: nil, reshuffle: false)
    new(challenge: challenge, team_count: team_count,
        team_size: team_size, reshuffle: reshuffle).call
  end

  def initialize(challenge:, team_count:, team_size:, reshuffle:)
    @challenge = challenge
    # nil.to_i is 0 and "3".to_i is 3, so params from JSON or text both work
    @team_count = team_count.to_i
    @team_size = team_size.to_i
    @reshuffle = ActiveModel::Type::Boolean.new.cast(reshuffle) == true
  end

  def call
    return { errors: ["This is not a team challenge"] } unless @challenge.team?

    # Teams are formed while sign-ups are done but the challenge hasn't begun
    unless @challenge.status == "published" && @challenge.starts_at > Time.current
      return {
        errors: ["Teams can only be formed while the challenge is published and has not started"]
      }
    end

    # Only active people are dealt in (a deactivated person is skipped)
    participants = @challenge.participants.active.order(:id).to_a

    count = resolve_team_count(participants.size)

    unless count && count >= MIN_TEAMS && count <= participants.size
      return {
        errors: [
          "Send a team_count (or team_size) that makes at least #{MIN_TEAMS} teams " \
          "and no more teams than participants (#{participants.size} have joined)"
        ]
      }
    end

    # Protect existing teams unless the admin explicitly asks to redo them
    if @challenge.teams.exists? && !@reshuffle
      return { errors: ["Teams already exist. Send reshuffle: true to rebuild them"] }
    end

    teams = []

    # All-or-nothing: if anything fails, no half-built teams are left behind
    Challenge.transaction do
      @challenge.lock!
      @challenge.teams.destroy_all if @reshuffle

      teams = Array.new(count) { |i| @challenge.teams.create!(name: "Team #{i + 1}") }

      participants.shuffle.each_with_index do |user, i|
        # i % count walks round and round the teams: 0, 1, 2, 0, 1, 2, ...
        teams[i % count].team_memberships.create!(user: user, challenge: @challenge)
      end
    end

    { teams: teams }
  rescue ActiveRecord::RecordInvalid => e
    { errors: e.record.errors.full_messages }
  end

  private

  # "team_count: 4" means 4 teams. "team_size: 5" means as many teams as
  # needed for about 5 people each (rounded up).
  def resolve_team_count(participant_count)
    return @team_count if @team_count.positive?
    return (participant_count / @team_size.to_f).ceil if @team_size.positive?

    nil
  end
end