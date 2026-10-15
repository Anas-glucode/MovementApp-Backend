class ChallengeParticipation < ApplicationRecord
  belongs_to :challenge
  belongs_to :user

  validates :user_id, uniqueness: {
    scope: :challenge_id,
    message: "has already joined this challenge"
  }

  validate :user_and_challenge_must_belong_to_same_company
  validate :challenge_must_be_open_for_joining

  private

  def user_and_challenge_must_belong_to_same_company
    return if user.blank? || challenge.blank?
    return if user.company_id == challenge.company_id

    errors.add(:user, "must belong to the same company as the challenge")
  end

  def challenge_must_be_open_for_joining
    return if challenge.blank?
    return if challenge.status == "published" &&
              challenge.starts_at.present? &&
              challenge.starts_at > Time.current

    errors.add(:challenge, "is not open for joining")
  end
end
