# Your original model merged with the new rules.
#
# A badge is a recipe: "earn it when ... reaches ...".
#   criteria_type says HOW it is measured, category says WHAT is measured.
#   company_id empty = a global badge everyone can earn.
class Badge < ApplicationRecord
  belongs_to :company, optional: true

  # CHANGED from dependent: :destroy. With :destroy, deleting a badge would
  # silently wipe it from every person who earned it. Now a badge that has
  # been earned simply cannot be deleted (the controller also says so nicely).
  has_many :user_badges, dependent: :restrict_with_error
  has_many :users, through: :user_badges

  # Which categories make sense for which kind of criteria.
  #   single_activity  one activity on its own reaches the target
  #                    (milestone = the person's Nth activity)
  #   cumulative       everything added up reaches the target
  #   daily_streak     N days in a row with enough activity
  #   weekly_streak    N weeks in a row with activity
  VALID_COMBINATIONS = {
    "single_activity" => %w[milestone steps distance duration],
    "cumulative" => %w[steps distance duration],
    "daily_streak" => %w[streak],
    "weekly_streak" => %w[streak]
  }.freeze

  CRITERIA_TYPES = VALID_COMBINATIONS.keys.freeze
  CATEGORIES = VALID_COMBINATIONS.values.flatten.uniq.freeze

  # Once someone has earned a badge, its target must not move. Changing a
  # target afterwards would make earlier winners look undeserving (or
  # latecomers' badges meaningless).
  LOCKED_ONCE_EARNED = %w[category criteria_type criteria_value].freeze

  validates :name, presence: true, uniqueness: { scope: :company_id },
                   length: { maximum: 100 }
  validates :category, presence: true
  validates :criteria_type, presence: true

  # allow_blank: a missing value already gets "can't be blank" above, so
  # these only speak up about values that are present but unknown.
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :criteria_type, inclusion: { in: CRITERIA_TYPES }, allow_blank: true

  # CHANGED from >= 0. A target of 0 is met by everyone instantly, which no
  # badge type here makes sense with.
  validates :criteria_value, presence: true,
                             numericality: { greater_than: 0 }

  validate :category_fits_criteria_type
  validate :criteria_locked_once_earned, on: :update

  def global?
    company_id.nil?
  end

  private

  def category_fits_criteria_type
    allowed = VALID_COMBINATIONS[criteria_type]
    return if allowed.nil? || category.blank? || allowed.include?(category)

    errors.add(:category, "#{category} cannot be used with #{criteria_type} badges")
  end

  def criteria_locked_once_earned
    changed = LOCKED_ONCE_EARNED.select { |field| will_save_change_to_attribute?(field) }
    return if changed.empty?
    return unless user_badges.exists?

    errors.add(:base, "#{changed.join(', ')} cannot be changed once someone has earned this badge")
  end
end