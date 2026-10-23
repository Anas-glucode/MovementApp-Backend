class Challenge < ApplicationRecord
  belongs_to :company
  belongs_to :scoring_rule_version

  has_many :challenge_participations, dependent: :destroy
  has_many :participants, through: :challenge_participations, source: :user
  has_many :challenge_activity_awards, dependent: :destroy
  has_many :teams, dependent: :destroy
  has_one :chat_room, dependent: :destroy

  CHALLENGE_TYPES = %w[individual team].freeze

  # How teams are ranked. "average" divides by team size so a team of 10
  # doesn't beat a team of 9 just by having one more person.
  TEAM_SCORING_METHODS = %w[average total].freeze

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
  LOCKED_AFTER_DRAFT = %w[
    starts_at ends_at challenge_type team_goal_points team_scoring_method
    registration_deadline max_participants
  ].freeze

  validates :challenge_type, presence: true, inclusion: { in: CHALLENGE_TYPES }
  validates :team_scoring_method, inclusion: { in: TEAM_SCORING_METHODS }
  validates :name, presence: true, length: { maximum: 150 }
  validates :starts_at, :ends_at, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  validates :team_goal_points,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true

  validates :max_participants,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true

  validate :ends_after_starts
  validate :registration_deadline_not_after_start
  validate :team_goal_only_for_team_challenges
  validate :scoring_rule_version_is_immutable, on: :update
  validate :status_change_must_be_allowed, on: :update
  validate :settings_locked_after_draft, on: :update

  def team?
    challenge_type == "team"
  end

  # ---- The challenge window ----
  # An activity belongs to the challenge it STARTED in. A run that begins
  # before the finish line counts in full, even if it ends a little after.
  # This is the same rule the daily cap uses ("the day it started").
  #
  # The end is exclusive (the three dots), so an activity starting exactly
  # at ends_at belongs to whatever comes next, not to this challenge.
  def window
    starts_at...ends_at
  end

  # ---- Joining and leaving ----

  # Joining closes at the registration deadline. With no deadline set, it
  # closes when the challenge starts, which is how it always worked.
  def registration_closes_at
    registration_deadline || starts_at
  end

  def open_for_joining?
    status == "published" &&
      registration_closes_at.present? &&
      Time.current < registration_closes_at
  end

  # Leaving is allowed until the start. After that, membership is locked
  # (requirement 8), because people leaving mid-challenge would unbalance teams.
  def open_for_leaving?
    status == "published" && starts_at.present? && Time.current < starts_at
  end

  def full?
    max_participants.present? && challenge_participations.count >= max_participants
  end

  # Activities from this challenge's active participants that an admin has
  # not looked at yet. Finalising must wait for these, otherwise their points
  # would be lost the moment the challenge closes. Deactivated people are
  # ignored, since their pending activities can't hold results hostage.
  def unreviewed_activities
    Activity
      .joins(:user)
      .where(users: { status: "active" })
      .where(user_id: challenge_participations.select(:user_id))
      .where(status: %w[pending under_review])
      .where(started_at: window)
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

  def registration_deadline_not_after_start
    return if registration_deadline.blank? || starts_at.blank?
    return if registration_deadline <= starts_at

    errors.add(:registration_deadline, "must be on or before the challenge start time")
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