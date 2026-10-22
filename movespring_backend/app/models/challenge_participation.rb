class ChallengeParticipation < ApplicationRecord
  belongs_to :challenge
  belongs_to :user

  validates :user_id, uniqueness: {
    scope: :challenge_id,
    message: "has already joined this challenge"
  }

  validate :user_and_challenge_must_belong_to_same_company
  validate :challenge_must_be_open_for_joining
  validate :challenge_must_have_room, on: :create

  private

  def user_and_challenge_must_belong_to_same_company
    return if user.blank? || challenge.blank?
    return if user.company_id == challenge.company_id

    errors.add(:user, "must belong to the same company as the challenge")
  end

  # Open means: published, and the registration deadline (or the start, if
  # there is no deadline) has not passed yet.
  def challenge_must_be_open_for_joining
    return if challenge.blank?
    return if challenge.open_for_joining?

    errors.add(:challenge, "is not open for joining")
  end

  # The "full" check is only reliable if the challenge row is locked while
  # joining, so two people can't grab the last spot together. The controller
  # does that lock.
  def challenge_must_have_room
    return if challenge.blank?
    return unless challenge.full?

    errors.add(:challenge, "is full")
  end
end