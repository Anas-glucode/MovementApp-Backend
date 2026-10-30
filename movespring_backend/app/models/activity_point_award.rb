class ActivityPointAward < ApplicationRecord
  belongs_to :activity
  belongs_to :scoring_rule_version

  validates :points,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }

  validates :activity_id, uniqueness: true

  # Every activity that earns points is the moment to check for badges.
  # Both ways an activity becomes scored (logged normally, or approved by
  # an admin) create one of these, so this one hook covers both.
  #
  # "after_create_commit" means it only runs once the activity and its points
  # are safely saved. Badges are a bonus: if the badge check ever breaks, the
  # activity must still stay logged, so errors are logged, never raised.
  after_create_commit :award_badges
  after_create_commit :evaluate_personal_records

  private

  def award_badges
    BadgeEvaluationService.new(activity.user, activity).evaluate
  rescue StandardError => e
    Rails.logger.error(
      "[Badges] activity=#{activity_id} evaluation failed: #{e.class}: #{e.message}"
    )
  end

  def evaluate_personal_records
  PersonalRecordEvaluationService.call(activity: activity)
rescue StandardError => e
  Rails.logger.error(
    "[PersonalRecords] activity=#{activity_id} evaluation failed: #{e.class}: #{e.message}"
  )
end
end