
class ActivityPointAward < ApplicationRecord
  belongs_to :activity
  belongs_to :scoring_rule_version

  validates :points,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }

  validates :activity_id, uniqueness: true
end
