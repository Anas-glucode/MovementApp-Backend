class TeamMembership < ApplicationRecord
  belongs_to :team
  belongs_to :user
  belongs_to :challenge

  validates :user_id, uniqueness: {
    scope: :challenge_id,
    message: "is already on a team in this challenge"
  }

  validate :challenge_matches_team
  validate :user_must_have_joined_challenge

  private

  # The copy of challenge_id must agree with the team's own challenge
  def challenge_matches_team
    return if team.blank? || challenge.blank?
    return if team.challenge_id == challenge_id

    errors.add(:challenge, "must match the team's challenge")
  end

  # Only people who signed up (and are in the same company) can be on a team
  def user_must_have_joined_challenge
    return if user.blank? || challenge.blank?
    return if challenge.challenge_participations.exists?(user_id: user_id)

    errors.add(:user, "must have joined the challenge")
  end
end