# Turns one eligible activity into challenge points, for each challenge the
# person has joined.
class ChallengeActivityScoringService
  class ScoringError < StandardError; end

  # A challenge accepts points while it is open for sign-up (published),
  # running (active) or in its cooling-off period after the end (finalizing).
  # Once it is completed its results are final and it takes nothing more.
  ALLOWED_CHALLENGE_STATUSES = %w[
    published
    active
    finalizing
  ].freeze

  # A challenge keeps using the rules version it was created with, even after
  # that version is retired, so "retired" is still fine here.
  ALLOWED_SCORING_STATUSES = %w[
    published
    retired
  ].freeze

  def self.call(challenge:, activity:)
    new(challenge: challenge, activity: activity).call
  end

  # Scores the activity into EVERY challenge the person has joined.
  #
  # Each challenge runs in its own "savepoint", like a separate tray in the
  # kitchen. If one tray is dropped (a broken rules version, say), only that
  # tray is thrown away. The activity, the personal points and the other
  # challenges carry on.
  def self.call_for_activity(activity:)
    return [] unless activity&.persisted? && activity.status == "eligible"

    activity.user
            .challenge_participations
            .includes(challenge: :scoring_rule_version)
            .filter_map do |participation|
      challenge = participation.challenge

      next unless ALLOWED_CHALLENGE_STATUSES.include?(challenge.status)

      # CHANGED: an activity counts if it STARTED inside the challenge.
      # Before, it had to start AND end inside, so a run crossing the start
      # or finish line counted for nothing.
      next unless challenge.window.cover?(activity.started_at)

      begin
        # requires_new: true is what makes this a savepoint instead of just
        # joining the outer transaction. A failure undoes ONLY this challenge.
        Activity.transaction(requires_new: true) do
          call(challenge: challenge, activity: activity)
        end
      rescue ScoringError => e
        # Don't hide it: log it so missing challenge points can be traced.
        Rails.logger.error(
          "[ChallengeScoring] challenge=#{challenge.id} " \
          "activity=#{activity.id} failed: #{e.message}"
        )

        nil # filter_map drops nil, so the other challenges still score
      end
    end
  end

  def initialize(challenge:, activity:)
    @challenge = challenge
    @activity = activity
  end

  def call
    @activity.with_lock do
      existing_award = ChallengeActivityAward.find_by(
        challenge_id: @challenge.id,
        activity_id: @activity.id
      )

      return existing_award if existing_award

      validate_eligibility!

      # One shared calculator does the maths for every kind of award
      rules = @challenge.scoring_rule_version.rules
      points = PointsCalculator.call(activity: @activity, rules: rules)

      # DAILY CAP: lock this person's row first, so two activities scored at the
      # same moment cannot both slip under the limit.
      @activity.user.lock!

      # Points this person already earned IN THIS CHALLENGE on the same local day
      already_awarded = ChallengeActivityAward
        .joins(:activity)
        .where(challenge_id: @challenge.id)
        .where(activities: {
          user_id: @activity.user_id,
          started_at: DailyPointCap.day_range(@activity)
        })
        .sum(:points)

      points = DailyPointCap.apply(
        points: points,
        activity: @activity,
        rules: rules,
        already_awarded: already_awarded
      )

      ChallengeActivityAward.create!(
        challenge: @challenge,
        activity: @activity,
        scoring_rule_version: @challenge.scoring_rule_version,
        points: points
      )
    end
  rescue PointsCalculator::CalculationError => e
    # Keep the services' own error type, with the same messages as before
    raise ScoringError, e.message
  rescue KeyError
    raise ScoringError, "Scoring rules are missing a required setting"
  end

  private

  def validate_eligibility!
    unless @challenge.persisted? &&
           ALLOWED_CHALLENGE_STATUSES.include?(@challenge.status)
      raise ScoringError, "Challenge is not available for scoring"
    end

    unless @activity.status == "eligible"
      raise ScoringError, "Activity must be eligible before scoring"
    end

    unless @activity.user.company_id == @challenge.company_id
      raise ScoringError, "Activity owner must belong to the challenge's company"
    end

    unless @challenge.challenge_participations.exists?(
      user_id: @activity.user_id
    )
      raise ScoringError, "Activity owner must participate in the challenge"
    end

    unless @challenge.window.cover?(@activity.started_at)
      raise ScoringError, "Activity must start within the challenge dates"
    end

    scoring_version = @challenge.scoring_rule_version

    unless ALLOWED_SCORING_STATUSES.include?(scoring_version.status) &&
           scoring_version.published_at.present?
      raise ScoringError, "Challenge scoring rules must have been published"
    end
  end
end