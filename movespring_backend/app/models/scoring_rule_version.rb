class ScoringRuleVersion < ApplicationRecord
  has_many :activity_point_awards, dependent: :restrict_with_error
  has_many :challenges, dependent: :restrict_with_error
  has_many :challenge_activity_awards, dependent: :restrict_with_error

  before_destroy :prevent_published_version_deletion

  STATUSES = %w[draft published retired].freeze
  LIVE_STATUSES = %w[published retired].freeze
  MULTIPLIER_KEYS = %w[baseline low moderate high].freeze

  validates :name, presence: true
  validates :version_number,
            numericality: { only_integer: true, greater_than: 0 },
            uniqueness: true

  validates :status, presence: true, inclusion: { in: STATUSES }

  validate :rules_must_be_a_hash
  validate :published_needs_a_publish_date
  validate :rules_must_be_complete, if: -> { LIVE_STATUSES.include?(status) }
  validate :published_rules_are_immutable, on: :update

  private

  def rules_must_be_a_hash
    return if rules.is_a?(Hash)

    errors.add(:rules, "must be an object")
  end

  def published_needs_a_publish_date
    return unless LIVE_STATUSES.include?(status)
    return if published_at.present?

    errors.add(:published_at, "must be set for a published scoring version")
  end

  def rules_must_be_complete
    return unless rules.is_a?(Hash)

    check_sport_rates
    check_intensity_multipliers
    check_intensity_bands
    check_optional_settings
  end

  def check_sport_rates
    rates = rules["sport_rates"]

    # Every supported sport must have a rate that is a real number above zero.
    # A rate of 0 would mean "this sport never earns anything", which is almost
    # certainly a typo, so we refuse it.
    valid = rates.is_a?(Hash) &&
            Activity::TYPES.all? { |type| positive_number?(rates[type]) }

    return if valid

    errors.add(:rules, "must include a positive sport rate for every supported activity type")
  end

  def check_intensity_multipliers
    multipliers = rules["intensity_multipliers"]

    valid = multipliers.is_a?(Hash) &&
            MULTIPLIER_KEYS.all? { |key| positive_number?(multipliers[key]) }

    unless valid
      errors.add(:rules, "must include positive baseline, low, moderate, and high intensity multipliers")
      return
    end

    # Trying harder should never earn LESS than trying less hard.
    unless multipliers["low"] <= multipliers["moderate"] &&
           multipliers["moderate"] <= multipliers["high"]
      errors.add(:rules, "intensity multipliers must go up: low <= moderate <= high")
    end
  end

  def check_intensity_bands
    bands = rules["intensity_bands"]
    unless bands.is_a?(Hash)
      errors.add(:rules, "intensity_bands must be an object")
      return
    end

    low_max = bands["low_max"]
    moderate_max = bands["moderate_max"]
    valid = low_max.is_a?(Integer) && moderate_max.is_a?(Integer) &&
            low_max >= 1 && low_max < moderate_max && moderate_max < 10

    unless valid
      errors.add(:rules, "intensity_bands needs whole numbers: 1 <= low_max < moderate_max < 10")
    end
  end

  def check_optional_settings
    if rules.key?("daily_point_cap")
      cap = rules["daily_point_cap"]
      unless cap.is_a?(Integer) && cap.positive?
        errors.add(:rules, "daily_point_cap must be a whole number > 0")
      end
    end

    if rules.key?("manual_multiplier")
      multiplier = rules["manual_multiplier"]
      unless non_negative_number?(multiplier) && multiplier <= 1
        errors.add(:rules, "manual_multiplier must be between 0 and 1")
      end
    end
  end

  def non_negative_number?(value)
    value.is_a?(Numeric) && value.to_f.finite? && value >= 0
  end

  def positive_number?(value)
    value.is_a?(Numeric) && value.to_f.finite? && value.positive?
  end

  def published_rules_are_immutable
    persisted_status = status_in_database
    return unless %w[published retired].include?(persisted_status)

    protected_fields = %w[name version_number published_at]

    changed_fields = protected_fields.select do |field|
      will_save_change_to_attribute?(field)
    end

    if changed_fields.any?
      message =
        if persisted_status == "retired"
          "Retired scoring rules cannot be edited"
        else
          "Published scoring rules cannot be edited; create a new version instead"
        end

      errors.add(:base, message)
    end

    if will_save_change_to_attribute?("rules")
      if persisted_status == "retired"
        unless changed_fields.any?
          errors.add(:base, "Retired scoring rules cannot be edited")
        end
      else
        errors.add(:rules, "cannot be changed after publishing; create a new version instead")
      end
    end

    if will_save_change_to_attribute?("status")
      if persisted_status == "retired"
        errors.add(:status, "cannot be changed once retired")
      elsif status != "retired"
        errors.add(:status, "must transition from published to retired")
      end
    end
  end

  def prevent_published_version_deletion
    return unless %w[published retired].include?(status_in_database)

    errors.add(
      :base,
      "Published or retired scoring versions cannot be deleted"
    )

    throw(:abort)
  end
end
