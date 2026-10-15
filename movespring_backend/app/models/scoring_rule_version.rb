class ScoringRuleVersion < ApplicationRecord
  has_many :activity_point_awards, dependent: :restrict_with_error

  before_destroy :prevent_published_version_deletion

  STATUSES = %w[draft published retired].freeze

  validates :name, presence: true
  validates :version_number,
            numericality: { only_integer: true, greater_than: 0 },
            uniqueness: true

  validates :status, presence: true, inclusion: { in: STATUSES }

  validate :rules_must_be_a_hash
  validate :published_version_requires_timestamp
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

  def published_rules_are_immutable
    return unless status_in_database == "published"

    protected_fields = %w[name version_number rules published_at]

    changed_fields = protected_fields.select do |field|
      will_save_change_to_attribute?(field)
    end

    if changed_fields.any?
      errors.add(
        :base,
        "Published scoring rules cannot be edited; create a new version instead"
      )
    end

    if will_save_change_to_attribute?("status") && status != "retired"
      errors.add(:status, "must transition from published to retired")
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
