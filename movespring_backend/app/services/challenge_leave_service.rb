# Takes ONE person out of a challenge before it starts. If they were dealt
# onto a team, the team spot goes too (people don't move between teams on
# their own: teams are random, requirement 8).
#
# Returns { left: true } or { errors: [...], reason: :closed / :not_joined }.
class ChallengeLeaveService
  def self.call(challenge:, user:)
    new(challenge: challenge, user: user).call
  end

  def initialize(challenge:, user:)
    @challenge = challenge
    @user = user
  end

  def call
    result = nil

    # All-or-nothing: leaving the challenge and leaving the team together.
    ChallengeParticipation.transaction do
      # Lock the challenge so a leave can't race with the start.
      @challenge.lock!

      participation = ChallengeParticipation.find_by(
        challenge_id: @challenge.id, user_id: @user.id
      )

      result =
        if !@challenge.open_for_leaving?
          { errors: ["You can only leave a challenge before it starts"], reason: :closed }
        elsif participation.nil?
          { errors: ["You have not joined this challenge"], reason: :not_joined }
        else
          TeamMembership.where(challenge_id: @challenge.id, user_id: @user.id).destroy_all
          participation.destroy!
          { left: true }
        end
    end

    result
  end
end
