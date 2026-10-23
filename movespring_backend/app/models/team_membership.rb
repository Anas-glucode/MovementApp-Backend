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

  # CHANGED: two new checks, only when a membership is first CREATED.
  # They are create-only on purpose: if someone is deactivated later, their
  # existing membership must stay valid, otherwise any later save touching it
  # would suddenly fail.
  validate :user_must_belong_to_challenge_company, on: :create
  validate :user_must_be_active, on: :create

  private

  # The copy of challenge_id must agree with the team's own challenge
  def challenge_matches_team
    return if team.blank? || challenge.blank?
    return if team.challenge_id == challenge_id

    errors.add(:challenge, "must match the team's challenge")
  end

  # Only people who signed up can be on a team
  def user_must_have_joined_challenge
    return if user.blank? || challenge.blank?
    return if challenge.challenge_participations.exists?(user_id: user_id)

    errors.add(:user, "must have joined the challenge")
  end

  # Checked directly here, not just through the sign-up check, so no other
  # code path can ever put an outsider on a team.
  def user_must_belong_to_challenge_company
    return if user.blank? || challenge.blank?
    return if user.company_id == challenge.company_id

    errors.add(:user, "must belong to the same company as the challenge")
  end

  # A deactivated person cannot be dealt onto a team.
  def user_must_be_active
    return if user.blank?
    return if user.active?

    errors.add(:user, "must be active")
  end
end