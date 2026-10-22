class Challenge < ApplicationRecord
  belongs_to :company
  belongs_to :scoring_rule_version

  has_many :challenge_participations, dependent: :destroy
  has_many :participants, through: :challenge_participations, source: :user
  has_many :challenge_activity_awards, dependent: :destroy
  has_many :teams, dependent: :destroy
  has_one :chat_room, dependent: :destroy

  CHALLENGE_TYPES = %w[individual team].freeze

  # The life of a challenge, like a film from script to release:
  #   draft       being written, admin can edit everything
  #   published   open for people to join, not started yet
  #   active      running, points are being earned
  #   finalizing  ended; late syncs and reviews can still add points
  #   completed   results are final and locked
  #   cancelled   called off
  STATUSES = %w[draft published active finalizing completed cancelled].freeze

  # Where each status is allowed to go next. Anything not listed is refused.
  STATUS_TRANSITIONS = {
    "draft" => %w[published cancelled],
    "published" => %w[active cancelled],
    "active" => %w[finalizing cancelled],
    "finalizing" => %w[completed],
    "completed" => [],
    "cancelled" => []
  }.freeze

  # Once a challenge leaves draft, the rules of the game must not change
  # under people's feet. Name and description may still be tidied up.
  LOCKED_AFTER_DRAFT = %w[starts_at ends_at challenge_type team_goal_points].freeze

  validates :challenge_type, presence: true, inclusion: { in: CHALLENGE_TYPES }
  validates :name, presence: true, length: { maximum: 150 }
  validates :starts_at, :ends_at, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  validates :team_goal_points,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true

  validate :ends_after_starts
  validate :team_goal_only_for_team_challenges
  validate :scoring_rule_version_is_immutable, on: :update
  validate :status_change_must_be_allowed, on: :update
  validate :settings_locked_after_draft, on: :update

  def team?
    challenge_type == "team"
  end

  # Activities from this challenge's participants, inside the challenge dates,
  # that an admin has not looked at yet. Finalising must wait for these,
  # otherwise their points would be lost the moment the challenge closes.
  def unreviewed_activities
    Activity
      .where(user_id: challenge_participations.select(:user_id))
      .where(status: %w[pending under_review])
      .where("started_at >= ? AND ended_at <= ?", starts_at, ends_at)
  end

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

  # An individual challenge has no teams, so a team goal makes no sense there
  def team_goal_only_for_team_challenges
    return if team_goal_points.blank?
    return if team?

    errors.add(:team_goal_points, "can only be set on team challenges")
  end

  def status_change_must_be_allowed
    return unless will_save_change_to_status?

    from = status_in_database
    allowed = STATUS_TRANSITIONS.fetch(from, [])
    return if allowed.include?(status)

    errors.add(:status, "cannot move from #{from} to #{status}")
  end

  def settings_locked_after_draft
    return if status_in_database == "draft"

    changed = LOCKED_AFTER_DRAFT.select { |field| will_save_change_to_attribute?(field) }
    return if changed.empty?

    errors.add(:base, "#{changed.join(', ')} are locked once a challenge is no longer a draft")
  end
end