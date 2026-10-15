class Challenge < ApplicationRecord
  belongs_to :company
  belongs_to :scoring_rule_version

  has_many :challenge_participations, dependent: :destroy
  has_many :participants, through: :challenge_participations, source: :user

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

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, "must be after the challenge start time")
  end
end
