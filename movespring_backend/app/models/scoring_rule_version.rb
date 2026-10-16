class ScoringRuleVersion < ApplicationRecord
  has_many :activity_point_awards, dependent: :restrict_with_error
  has_many :challenges, dependent: :restrict_with_error
  has_many :challenge_activity_awards, dependent: :restrict_with_error

  before_destroy :prevent_published_version_deletion

  STATUSES = %w[draft published retired].freeze

  validates :name, presence: true
  validates :version_number,
            numericality: { only_integer: true, greater_than: 0 },
            uniqueness: true

  validates :status, presence: true, inclusion: { in: STATUSES }

  validate :rules_must_be_a_hash
  validate :published_version_requires_timestamp
  validate :published_rules_have_valid_configuration
  validate :published_rules_are_immutable, on: :update

  private

  def rules_must_be_a_hash
    return if rules.is_a?(Hash)

    errors.add(:rules, "must be a JSON object")
  end

  def published_version_requires_timestamp
    return unless status == "published"
    return if published_at.present?

    errors.add(:published_at, "must be set for a published scoring version")
  end

  def published_rules_have_valid_configuration
    return unless status == "published"
    return unless rules.is_a?(Hash)

    supported_types = %w[
      walking running cycling swimming football strength_training golf
    ]
    sport_rates = rules["sport_rates"]

    unless sport_rates.is_a?(Hash) &&
           supported_types.all? do |activity_type|
             positive_number?(sport_rates[activity_type])
           end
      errors.add(
        :rules,
        "must include a positive sport rate for every supported activity type"
      )
    end

    required_multipliers = %w[baseline low moderate high]
    multipliers = rules["intensity_multipliers"]

    unless multipliers.is_a?(Hash) &&
           required_multipliers.all? do |intensity|
             positive_number?(multipliers[intensity])
           end
      errors.add(
        :rules,
        "must include positive baseline, low, moderate, and high intensity multipliers"
      )
    end

    bands = rules["intensity_bands"]
    low_max = bands.is_a?(Hash) ? bands["low_max"] : nil
    moderate_max = bands.is_a?(Hash) ? bands["moderate_max"] : nil

    valid_bands =
      low_max.is_a?(Integer) &&
      moderate_max.is_a?(Integer) &&
      low_max >= 1 &&
      moderate_max > low_max &&
      moderate_max <= 9

    unless valid_bands
      errors.add(
        :rules,
        "must include valid intensity bands with low_max below moderate_max and moderate_max between 2 and 9"
      )
    end
  end

  def positive_number?(value)
    value.is_a?(Numeric) && value.to_f.finite? && value.to_f > 0
  end

  def published_rules_are_immutable
    persisted_status = status_in_database
    return unless %w[published retired].include?(persisted_status)

    protected_fields = %w[name version_number rules published_at]

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
