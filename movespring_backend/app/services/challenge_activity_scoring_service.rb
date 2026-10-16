class ChallengeActivityScoringService
  class ScoringError < StandardError; end

  ALLOWED_CHALLENGE_STATUSES = %w[
    published
    active
    completed
  ].freeze

  ALLOWED_SCORING_STATUSES = %w[
    published
    retired
  ].freeze

  def self.call(challenge:, activity:)
    new(challenge: challenge, activity: activity).call
  end

  def self.call_for_activity(activity:)
  return [] unless activity&.persisted? && activity.status == "eligible"

  activity.user
          .challenge_participations
          .includes(challenge: :scoring_rule_version)
          .filter_map do |participation|
    challenge = participation.challenge

    next unless ALLOWED_CHALLENGE_STATUSES.include?(challenge.status)

    next unless activity.started_at >= challenge.starts_at &&
                activity.ended_at <= challenge.ends_at

    call(
      challenge: challenge,
      activity: activity
    )
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

      rules = @challenge.scoring_rule_version.rules
      sport_rates = rules.fetch("sport_rates")
      intensity_multipliers = rules.fetch("intensity_multipliers")

      sport_rate = sport_rates.fetch(@activity.activity_type) do
        raise ScoringError, "No scoring rate for this activity type"
      end

      intensity = intensity_band(rules)
      multiplier = intensity_multipliers.fetch(intensity) do
        raise ScoringError, "No multiplier configured for #{intensity}"
      end

      minutes = @activity.duration_seconds / 60.0
      points = (minutes * sport_rate.to_f * multiplier.to_f).round

      ChallengeActivityAward.create!(
        challenge: @challenge,
        activity: @activity,
        scoring_rule_version: @challenge.scoring_rule_version,
        points: points
      )
    end
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

    unless @activity.started_at >= @challenge.starts_at &&
           @activity.ended_at <= @challenge.ends_at
      raise ScoringError, "Activity must fall within the challenge dates"
    end

    scoring_version = @challenge.scoring_rule_version

    unless ALLOWED_SCORING_STATUSES.include?(scoring_version.status) &&
           scoring_version.published_at.present?
      raise ScoringError, "Challenge scoring rules must have been published"
    end
  end

  def intensity_band(rules)
    intensity = @activity.reported_intensity

    return "baseline" if intensity.nil?

    bands = rules.fetch("intensity_bands")
    low_max = bands.fetch("low_max")
    moderate_max = bands.fetch("moderate_max")

    if intensity <= low_max
      "low"
    elsif intensity <= moderate_max
      "moderate"
    else
      "high"
    end
  end
end