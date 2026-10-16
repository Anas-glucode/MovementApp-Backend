class ChallengeActivityAward < ApplicationRecord
  belongs_to :challenge
  belongs_to :activity
  belongs_to :scoring_rule_version

  validates :points,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }

  validates :activity_id, uniqueness: { scope: :challenge_id }

  validate :scoring_version_matches_challenge

  private

  def scoring_version_matches_challenge
    return if challenge.blank? || scoring_rule_version.blank?
    return if challenge.scoring_rule_version_id == scoring_rule_version_id

    errors.add(
      :scoring_rule_version,
      "must match the challenge's scoring rules"
    )
  end
end
