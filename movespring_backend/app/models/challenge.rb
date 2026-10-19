class Challenge < ApplicationRecord
  belongs_to :company
  belongs_to :scoring_rule_version

  has_many :challenge_participations, dependent: :destroy
  has_many :participants, through: :challenge_participations, source: :user
  has_many :challenge_activity_awards, dependent: :destroy

  has_one :chat_room, dependent: :destroy

  STATUSES = %w[
    draft
    published
    active
    completed
    cancelled
  ].freeze

  validates :name, presence: true, length: { maximum: 150 }
  validates :starts_at, :ends_at, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  validate :ends_after_starts
  validate :scoring_rule_version_is_immutable, on: :update

  private

  def scoring_rule_version_is_immutable
    return unless will_save_change_to_scoring_rule_version_id?

    errors.add(
      :scoring_rule_version,
      "cannot be changed after the challenge is created"
    )
  end

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, "must be after the challenge start time")
  end
end
