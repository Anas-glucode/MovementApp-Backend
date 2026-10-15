class ActivityReview < ApplicationRecord
  belongs_to :activity
  belongs_to :reviewer, class_name: "User"

  DECISIONS = %w[approved rejected].freeze

  validates :decision, presence: true, inclusion: { in: DECISIONS }
  validates :reviewed_at, presence: true
  validates :activity_id, uniqueness: true
  validates :reason, presence: true, if: -> { decision == "rejected" }

  validate :reviewer_must_be_company_admin
  validate :reviewer_must_belong_to_activity_company

  private

  def reviewer_must_be_company_admin
    return if reviewer.blank?
    return if reviewer.company_admin?

    errors.add(:reviewer, "must be a company administrator")
  end

  def reviewer_must_belong_to_activity_company
    return if activity.blank? || reviewer.blank?
    return if activity.user.company_id == reviewer.company_id

    errors.add(:reviewer, "must belong to the same company as the activity")
  end
end
